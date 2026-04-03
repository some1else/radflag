import Darwin
import Foundation

enum PowerSource: String, Codable, Equatable {
    case battery
    case ac
    case unknown

    var displayName: String {
        switch self {
        case .battery:
            return "Battery"
        case .ac:
            return "AC Power"
        case .unknown:
            return "Unknown"
        }
    }
}

struct LoadSample: Equatable {
    let timestamp: Date
    let loadAverage: Double
    let powerSource: PowerSource
}

struct ProcessCPUSnapshot: Equatable {
    let pid: pid_t
    let name: String
    let totalCPUTime: UInt64
}

struct ProcessCPUSample: Equatable {
    let timestamp: Date
    let cpuPercent: Double
}

struct ProcessOffender: Equatable {
    let pid: pid_t
    let name: String
    let averageCPUPercent: Double

    var displayName: String {
        "\(name) (pid \(pid))"
    }
}

struct MonitorSettings: Codable, Equatable {
    var thresholdRatio: Double = 1.5
    var processCPUThresholdPercent: Double = 100
    var soundEnabled: Bool = true
    var launchAtLogin: Bool = true
}

enum AlertTriggerReason: Equatable {
    case load
    case process
    case loadAndProcess

    init?(loadActive: Bool, processActive: Bool) {
        switch (loadActive, processActive) {
        case (false, false):
            return nil
        case (true, false):
            self = .load
        case (false, true):
            self = .process
        case (true, true):
            self = .loadAndProcess
        }
    }

    var displayName: String {
        switch self {
        case .load:
            return "Elevated load"
        case .process:
            return "Rogue process"
        case .loadAndProcess:
            return "Load + process"
        }
    }
}

enum AlertState: Equatable {
    case ok
    case high
    case muted(until: Date)

    var isElevated: Bool {
        switch self {
        case .ok:
            return false
        case .high, .muted:
            return true
        }
    }

    var muteUntil: Date? {
        if case let .muted(until) = self {
            return until
        }
        return nil
    }
}

enum NotificationKind: Equatable {
    case enteredHigh
    case repeatedHigh
}

struct NotificationRequest: Equatable {
    let kind: NotificationKind
    let timestamp: Date
}

struct MonitorSnapshot: Equatable {
    var latestSample: LoadSample?
    var recentAverage: Double?
    var baselineAverage: Double?
    var ratio: Double?
    var topProcess: ProcessOffender?
    var processOffender: ProcessOffender?
    var triggerReason: AlertTriggerReason?
    var sampleCount: Int
    var alertState: AlertState
    var lastAlertDate: Date?
    var isWarmingUp: Bool

    static let empty = MonitorSnapshot(
        latestSample: nil,
        recentAverage: nil,
        baselineAverage: nil,
        ratio: nil,
        topProcess: nil,
        processOffender: nil,
        triggerReason: nil,
        sampleCount: 0,
        alertState: .ok,
        lastAlertDate: nil,
        isWarmingUp: true
    )

    var isElevated: Bool {
        alertState.isElevated
    }
}

struct MonitorUpdate: Equatable {
    let snapshot: MonitorSnapshot
    let notification: NotificationRequest?
}
