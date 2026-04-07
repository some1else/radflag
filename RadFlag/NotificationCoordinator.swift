import Foundation
import UserNotifications

@MainActor
protocol NotificationCoordinating {
    func requestAuthorization()
    func sendAlert(
        for snapshot: MonitorSnapshot,
        kind: NotificationKind,
        soundEnabled: Bool,
        loadWindowText: String,
        processWindowText: String
    )
}

@MainActor
final class NotificationCoordinator: NotificationCoordinating {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
        }
    }

    func sendAlert(
        for snapshot: MonitorSnapshot,
        kind: NotificationKind,
        soundEnabled: Bool,
        loadWindowText: String,
        processWindowText: String
    ) {
        guard let triggerReason = snapshot.triggerReason else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title(for: triggerReason, kind: kind, loadWindowText: loadWindowText)
        content.body = body(
            for: snapshot,
            triggerReason: triggerReason,
            loadWindowText: loadWindowText,
            processWindowText: processWindowText
        )
        content.sound = soundEnabled ? .default : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { _ in
        }
    }

    private func title(for triggerReason: AlertTriggerReason, kind: NotificationKind, loadWindowText: String) -> String {
        switch (triggerReason, kind) {
        case (.load, .enteredHigh):
            return "RadFlag: high \(loadWindowText) load on battery"
        case (.load, .repeatedHigh):
            return "RadFlag: load still high on battery"
        case (.process, .enteredHigh):
            return "RadFlag: rogue process on battery"
        case (.process, .repeatedHigh):
            return "RadFlag: process still burning CPU"
        case (.loadAndProcess, .enteredHigh):
            return "RadFlag: load spike and rogue process"
        case (.loadAndProcess, .repeatedHigh):
            return "RadFlag: load and process still elevated"
        }
    }

    private func body(
        for snapshot: MonitorSnapshot,
        triggerReason: AlertTriggerReason,
        loadWindowText: String,
        processWindowText: String
    ) -> String {
        var segments: [String] = []

        if triggerReason == .load || triggerReason == .loadAndProcess {
            if
                let recentAverage = snapshot.recentAverage,
                let baselineAverage = snapshot.baselineAverage,
                let ratio = snapshot.ratio
            {
                segments.append(
                    String(
                        format: "\(loadWindowText) load %.2f vs baseline %.2f (%.2fx).",
                        recentAverage,
                        baselineAverage,
                        ratio
                    )
                )
            }
        }

        if
            (triggerReason == .process || triggerReason == .loadAndProcess),
            let processOffender = snapshot.processOffender
        {
            segments.append(
                String(
                    format: "%@ (pid %d) averaged %.0f%% CPU over the last \(processWindowText).",
                    processOffender.name,
                    Int32(processOffender.pid),
                    processOffender.averageCPUPercent
                )
            )
        }

        return segments.joined(separator: " ")
    }
}
