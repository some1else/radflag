import Foundation

final class MonitorEngine {
    static let maxSamples = 120
    static let recentWindowSize = 15
    static let minimumSampleCount = 30
    static let clearRatio = 1.3
    static let minimumRecentAverage = 1.0
    static let repeatInterval: TimeInterval = 15 * 60
    static let muteInterval: TimeInterval = 60 * 60
    private static let baselineFloor = 0.01

    private(set) var samples: [LoadSample] = []
    private(set) var snapshot: MonitorSnapshot = .empty

    func processSample(load15: Double, powerSource: PowerSource, at date: Date, settings: MonitorSettings) -> MonitorUpdate {
        let sample = LoadSample(timestamp: date, load15: load15, powerSource: powerSource)
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }

        let metrics = buildMetrics()
        let update = updateState(using: metrics, at: date, settings: settings)
        snapshot = update.snapshot
        return update
    }

    @discardableResult
    func muteForOneHour(at date: Date = Date()) -> MonitorSnapshot {
        guard snapshot.isElevated else {
            return snapshot
        }

        snapshot.alertState = .muted(until: date.addingTimeInterval(Self.muteInterval))
        return snapshot
    }

    @discardableResult
    func unmute() -> MonitorSnapshot {
        guard case .muted = snapshot.alertState else {
            return snapshot
        }

        snapshot.alertState = .high
        return snapshot
    }

    private func updateState(using metrics: WindowMetrics, at date: Date, settings: MonitorSettings) -> MonitorUpdate {
        var nextAlertState = snapshot.alertState
        var lastAlertDate = snapshot.lastAlertDate
        var notification: NotificationRequest?

        if case let .muted(until) = nextAlertState, date >= until {
            nextAlertState = .high
        }

        if !metrics.canEvaluate || metrics.powerSource != .battery {
            nextAlertState = .ok
        } else {
            switch nextAlertState {
            case .ok:
                if metrics.meetsTriggerThreshold(thresholdRatio: settings.thresholdRatio) {
                    nextAlertState = .high
                    lastAlertDate = date
                    notification = NotificationRequest(kind: .enteredHigh, timestamp: date)
                }
            case .high:
                if metrics.meetsClearThreshold {
                    if shouldSendRepeatNotification(now: date, lastAlertDate: lastAlertDate) {
                        lastAlertDate = date
                        notification = NotificationRequest(kind: .repeatedHigh, timestamp: date)
                    }
                } else {
                    nextAlertState = .ok
                }
            case let .muted(until):
                if metrics.meetsClearThreshold {
                    if date >= until {
                        nextAlertState = .high
                        if shouldSendRepeatNotification(now: date, lastAlertDate: lastAlertDate) {
                            lastAlertDate = date
                            notification = NotificationRequest(kind: .repeatedHigh, timestamp: date)
                        }
                    } else {
                        nextAlertState = .muted(until: until)
                    }
                } else {
                    nextAlertState = .ok
                }
            }
        }

        let nextSnapshot = MonitorSnapshot(
            latestSample: metrics.latestSample,
            recentAverage: metrics.recentAverage,
            baselineAverage: metrics.baselineAverage,
            ratio: metrics.ratio,
            sampleCount: metrics.sampleCount,
            alertState: nextAlertState,
            lastAlertDate: lastAlertDate,
            isWarmingUp: !metrics.canEvaluate
        )

        return MonitorUpdate(snapshot: nextSnapshot, notification: notification)
    }

    private func buildMetrics() -> WindowMetrics {
        let latestSample = samples.last
        let recentSamples = Array(samples.suffix(Self.recentWindowSize))
        let baselineSamples = Array(samples.dropLast(min(Self.recentWindowSize, samples.count)).suffix(Self.maxSamples - Self.recentWindowSize))

        let recentAverage = average(for: recentSamples)
        let baselineAverage = average(for: baselineSamples)
        let ratio = baselineAverage.map { baseline -> Double in
            guard let recentAverage else { return 0 }
            return recentAverage / max(baseline, Self.baselineFloor)
        }

        let canEvaluate = samples.count >= Self.minimumSampleCount
            && recentSamples.count == Self.recentWindowSize
            && !baselineSamples.isEmpty
            && ratio != nil

        return WindowMetrics(
            latestSample: latestSample,
            recentAverage: recentAverage,
            baselineAverage: baselineAverage,
            ratio: ratio,
            sampleCount: samples.count,
            powerSource: latestSample?.powerSource ?? .unknown,
            canEvaluate: canEvaluate
        )
    }

    private func average(for samples: [LoadSample]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }
        let total = samples.reduce(0) { $0 + $1.load15 }
        return total / Double(samples.count)
    }

    private func shouldSendRepeatNotification(now: Date, lastAlertDate: Date?) -> Bool {
        guard let lastAlertDate else {
            return true
        }
        return now.timeIntervalSince(lastAlertDate) >= Self.repeatInterval
    }
}

private struct WindowMetrics {
    let latestSample: LoadSample?
    let recentAverage: Double?
    let baselineAverage: Double?
    let ratio: Double?
    let sampleCount: Int
    let powerSource: PowerSource
    let canEvaluate: Bool

    func meetsTriggerThreshold(thresholdRatio: Double) -> Bool {
        guard canEvaluate, let recentAverage, let ratio else {
            return false
        }

        return recentAverage >= MonitorEngine.minimumRecentAverage && ratio >= thresholdRatio
    }

    var meetsClearThreshold: Bool {
        guard canEvaluate, let recentAverage, let ratio else {
            return false
        }

        return recentAverage >= MonitorEngine.minimumRecentAverage && ratio >= MonitorEngine.clearRatio
    }
}
