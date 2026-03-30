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
    let load15: Double
    let powerSource: PowerSource
}

struct MonitorSettings: Codable, Equatable {
    var thresholdRatio: Double = 1.5
    var soundEnabled: Bool = true
    var launchAtLogin: Bool = true
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
    var sampleCount: Int
    var alertState: AlertState
    var lastAlertDate: Date?
    var isWarmingUp: Bool

    static let empty = MonitorSnapshot(
        latestSample: nil,
        recentAverage: nil,
        baselineAverage: nil,
        ratio: nil,
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
