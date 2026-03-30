import Foundation
import UserNotifications

@MainActor
protocol NotificationCoordinating {
    func requestAuthorization()
    func sendAlert(for snapshot: MonitorSnapshot, kind: NotificationKind, soundEnabled: Bool)
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

    func sendAlert(for snapshot: MonitorSnapshot, kind: NotificationKind, soundEnabled: Bool) {
        guard
            let recentAverage = snapshot.recentAverage,
            let baselineAverage = snapshot.baselineAverage,
            let ratio = snapshot.ratio
        else {
            return
        }

        let content = UNMutableNotificationContent()
        switch kind {
        case .enteredHigh:
            content.title = "Load Watcher: high load on battery"
        case .repeatedHigh:
            content.title = "Load Watcher: still high on battery"
        }
        content.body = String(
            format: "15m load %.2f vs baseline %.2f (%.2fx).",
            recentAverage,
            baselineAverage,
            ratio
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
}
