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

struct ProcessCPUObservation: Equatable {
    let timestamp: Date
    let totalCPUTime: UInt64
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
    var baselineRiseFactor: Double = 0.03
    var baselineRecoveryFactor: Double = 0.10
    var sampleIntervalSeconds: Double = 20
    var loadWindowSeconds: Double = 5 * 60
    var processWindowSeconds: Double = 5 * 60
    var repeatIntervalSeconds: Double = 5 * 60
    var muteIntervalSeconds: Double = 20 * 60

    enum CodingKeys: String, CodingKey {
        case thresholdRatio
        case processCPUThresholdPercent
        case soundEnabled
        case launchAtLogin
        case baselineRiseFactor
        case baselineRecoveryFactor
        case sampleIntervalSeconds
        case loadWindowSeconds
        case processWindowSeconds
        case repeatIntervalSeconds
        case muteIntervalSeconds
    }

    private enum TimingRange {
        static let sampleInterval = strideRange(10, 60, 5)
        static let loadWindow = strideRange(2 * 60, 15 * 60, 60)
        static let processWindow = strideRange(2 * 60, 15 * 60, 60)
        static let repeatInterval = strideRange(60, 30 * 60, 60)
        static let muteInterval = strideRange(5 * 60, 60 * 60, 5 * 60)

        private static func strideRange(_ minimum: Double, _ maximum: Double, _ step: Double) -> ClosedRange<Double> {
            _ = step
            return minimum...maximum
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thresholdRatio = try container.decodeIfPresent(Double.self, forKey: .thresholdRatio) ?? 1.5
        processCPUThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .processCPUThresholdPercent) ?? 100
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        baselineRiseFactor = try container.decodeIfPresent(Double.self, forKey: .baselineRiseFactor) ?? 0.03
        baselineRecoveryFactor = try container.decodeIfPresent(Double.self, forKey: .baselineRecoveryFactor) ?? 0.10
        sampleIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .sampleIntervalSeconds) ?? 20
        loadWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .loadWindowSeconds) ?? 5 * 60
        processWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .processWindowSeconds) ?? 5 * 60
        repeatIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .repeatIntervalSeconds) ?? 5 * 60
        muteIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .muteIntervalSeconds) ?? 20 * 60
        normalizeTiming()
        enforceBaselineFactorOrder()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thresholdRatio, forKey: .thresholdRatio)
        try container.encode(processCPUThresholdPercent, forKey: .processCPUThresholdPercent)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(baselineRiseFactor, forKey: .baselineRiseFactor)
        try container.encode(baselineRecoveryFactor, forKey: .baselineRecoveryFactor)
        try container.encode(sampleIntervalSeconds, forKey: .sampleIntervalSeconds)
        try container.encode(loadWindowSeconds, forKey: .loadWindowSeconds)
        try container.encode(processWindowSeconds, forKey: .processWindowSeconds)
        try container.encode(repeatIntervalSeconds, forKey: .repeatIntervalSeconds)
        try container.encode(muteIntervalSeconds, forKey: .muteIntervalSeconds)
    }

    mutating func enforceBaselineFactorOrder() {
        baselineRecoveryFactor = max(baselineRecoveryFactor, baselineRiseFactor)
    }

    mutating func normalizeTiming() {
        sampleIntervalSeconds = snapped(sampleIntervalSeconds, within: TimingRange.sampleInterval, step: 5)
        loadWindowSeconds = max(
            snapped(loadWindowSeconds, within: TimingRange.loadWindow, step: 60),
            sampleIntervalSeconds
        )
        processWindowSeconds = max(
            snapped(processWindowSeconds, within: TimingRange.processWindow, step: 60),
            sampleIntervalSeconds
        )
        repeatIntervalSeconds = max(
            snapped(repeatIntervalSeconds, within: TimingRange.repeatInterval, step: 60),
            sampleIntervalSeconds
        )
        muteIntervalSeconds = max(
            snapped(muteIntervalSeconds, within: TimingRange.muteInterval, step: 5 * 60),
            sampleIntervalSeconds
        )
    }

    func normalized() -> MonitorSettings {
        var copy = self
        copy.normalizeTiming()
        copy.enforceBaselineFactorOrder()
        return copy
    }

    private func snapped(_ value: Double, within range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let snappedSteps = ((clamped - range.lowerBound) / step).rounded()
        let snappedValue = range.lowerBound + snappedSteps * step
        return min(max(snappedValue, range.lowerBound), range.upperBound)
    }
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

struct MonitoringStatusRow: Equatable {
    let label: String
    let value: String
}

struct MonitorUpdate: Equatable {
    let snapshot: MonitorSnapshot
    let notification: NotificationRequest?
}
