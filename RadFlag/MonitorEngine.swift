import Darwin
import Foundation

final class MonitorEngine {
    static let sampleInterval: TimeInterval = 20
    static let maxSamples = 120
    static let recentWindowSize = 15
    static let minimumSampleCount = 30
    static let processWindowDuration: TimeInterval = 5 * 60
    static let minimumProcessSampleCount = Int(processWindowDuration / sampleInterval) + 1
    static let clearRatio = 1.3
    static let minimumRecentAverage = 1.0
    static let repeatInterval: TimeInterval = 5 * 60
    static let muteInterval: TimeInterval = 20 * 60
    private static let baselineFloor = 0.01
    private static let nanosecondsPerSecond = 1_000_000_000.0

    private(set) var samples: [LoadSample] = []
    private(set) var snapshot: MonitorSnapshot = .empty
    private var processHistories: [pid_t: ProcessHistory] = [:]

    func processSample(
        loadAverage: Double,
        powerSource: PowerSource,
        processSnapshots: [ProcessCPUSnapshot],
        at date: Date,
        settings: MonitorSettings
    ) -> MonitorUpdate {
        let sample = LoadSample(timestamp: date, loadAverage: loadAverage, powerSource: powerSource)
        samples.append(sample)
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }

        let loadMetrics = buildLoadMetrics()
        let topProcess = updateProcessHistories(with: processSnapshots, at: date)
        let processOffender = processOffender(from: topProcess, settings: settings)
        let update = updateState(
            using: loadMetrics,
            topProcess: topProcess,
            processOffender: processOffender,
            at: date,
            settings: settings
        )
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

    private func updateState(
        using loadMetrics: LoadMetrics,
        topProcess: ProcessOffender?,
        processOffender: ProcessOffender?,
        at date: Date,
        settings: MonitorSettings
    ) -> MonitorUpdate {
        var nextAlertState = snapshot.alertState
        var lastAlertDate = snapshot.lastAlertDate
        var notification: NotificationRequest?

        if case let .muted(until) = nextAlertState, date >= until {
            nextAlertState = .high
        }

        let loadIsActive = loadMetrics.powerSource == .battery
            && loadMetrics.meetsThreshold(
                thresholdRatio: settings.thresholdRatio,
                isAlreadyElevated: snapshot.alertState.isElevated
            )
        let processIsActive = loadMetrics.powerSource == .battery && processOffender != nil
        let triggerReason = AlertTriggerReason(loadActive: loadIsActive, processActive: processIsActive)

        if loadMetrics.powerSource != .battery || triggerReason == nil {
            nextAlertState = .ok
        } else {
            switch nextAlertState {
            case .ok:
                nextAlertState = .high
                lastAlertDate = date
                notification = NotificationRequest(kind: .enteredHigh, timestamp: date)
            case .high:
                if shouldSendRepeatNotification(now: date, lastAlertDate: lastAlertDate) {
                    lastAlertDate = date
                    notification = NotificationRequest(kind: .repeatedHigh, timestamp: date)
                }
            case let .muted(until):
                if date >= until {
                    nextAlertState = .high
                    if shouldSendRepeatNotification(now: date, lastAlertDate: lastAlertDate) {
                        lastAlertDate = date
                        notification = NotificationRequest(kind: .repeatedHigh, timestamp: date)
                    }
                } else {
                    nextAlertState = .muted(until: until)
                }
            }
        }

        let nextSnapshot = MonitorSnapshot(
            latestSample: loadMetrics.latestSample,
            recentAverage: loadMetrics.recentAverage,
            baselineAverage: loadMetrics.baselineAverage,
            ratio: loadMetrics.ratio,
            topProcess: topProcess,
            processOffender: processOffender,
            triggerReason: triggerReason,
            sampleCount: loadMetrics.sampleCount,
            alertState: nextAlertState,
            lastAlertDate: lastAlertDate,
            isWarmingUp: !loadMetrics.canEvaluate
        )

        return MonitorUpdate(snapshot: nextSnapshot, notification: notification)
    }

    private func buildLoadMetrics() -> LoadMetrics {
        let latestSample = samples.last
        let recentSamples = Array(samples.suffix(Self.recentWindowSize))
        let baselineSamples = Array(
            samples
                .dropLast(min(Self.recentWindowSize, samples.count))
                .suffix(Self.maxSamples - Self.recentWindowSize)
        )

        let recentAverage = average(for: recentSamples)
        let baselineAverage = average(for: baselineSamples)
        let ratio = baselineAverage.map { baseline -> Double in
            guard let recentAverage else {
                return 0
            }
            return recentAverage / max(baseline, Self.baselineFloor)
        }

        let canEvaluate = samples.count >= Self.minimumSampleCount
            && recentSamples.count == Self.recentWindowSize
            && !baselineSamples.isEmpty
            && ratio != nil

        return LoadMetrics(
            latestSample: latestSample,
            recentAverage: recentAverage,
            baselineAverage: baselineAverage,
            ratio: ratio,
            sampleCount: samples.count,
            powerSource: latestSample?.powerSource ?? .unknown,
            canEvaluate: canEvaluate
        )
    }

    private func updateProcessHistories(with snapshots: [ProcessCPUSnapshot], at date: Date) -> ProcessOffender? {
        var nextHistories: [pid_t: ProcessHistory] = [:]

        for snapshot in snapshots where snapshot.pid > 0 {
            var history = processHistories[snapshot.pid] ?? ProcessHistory(name: snapshot.name, observations: [])
            history.name = snapshot.name

            if let lastObservation = history.observations.last {
                if snapshot.totalCPUTime < lastObservation.totalCPUTime {
                    history.observations.removeAll()
                } else if date <= lastObservation.timestamp {
                    nextHistories[snapshot.pid] = history
                    continue
                }
            }

            history.observations.append(
                ProcessCPUObservation(timestamp: date, totalCPUTime: snapshot.totalCPUTime)
            )
            pruneObservations(&history.observations, latestTimestamp: date)
            nextHistories[snapshot.pid] = history
        }

        processHistories = nextHistories
        return topProcess(in: nextHistories)
    }

    private func topProcess(in histories: [pid_t: ProcessHistory]) -> ProcessOffender? {
        histories.reduce(into: nil as ProcessOffender?) { best, entry in
            let (pid, history) = entry
            guard let averageCPUPercent = averageCPUPercent(for: history) else {
                return
            }

            if best == nil || averageCPUPercent > best!.averageCPUPercent {
                best = ProcessOffender(pid: pid, name: history.name, averageCPUPercent: averageCPUPercent)
            }
        }
    }

    private func processOffender(from topProcess: ProcessOffender?, settings: MonitorSettings) -> ProcessOffender? {
        guard
            let topProcess,
            topProcess.averageCPUPercent > settings.processCPUThresholdPercent
        else {
            return nil
        }

        return topProcess
    }

    private func average(for samples: [LoadSample]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce(0) { $0 + $1.loadAverage }
        return total / Double(samples.count)
    }

    private func averageCPUPercent(for history: ProcessHistory) -> Double? {
        guard
            let latestObservation = history.observations.last,
            let anchorObservation = anchorObservation(in: history.observations, latestTimestamp: latestObservation.timestamp)
        else {
            return nil
        }

        let elapsed = latestObservation.timestamp.timeIntervalSince(anchorObservation.timestamp)
        guard
            elapsed >= Self.processWindowDuration,
            latestObservation.totalCPUTime >= anchorObservation.totalCPUTime
        else {
            return nil
        }

        let delta = latestObservation.totalCPUTime - anchorObservation.totalCPUTime
        return cpuPercent(deltaCPUTime: delta, elapsed: elapsed)
    }

    private func anchorObservation(
        in observations: [ProcessCPUObservation],
        latestTimestamp: Date
    ) -> ProcessCPUObservation? {
        let cutoffTimestamp = latestTimestamp.addingTimeInterval(-Self.processWindowDuration)
        return observations.last { $0.timestamp <= cutoffTimestamp }
    }

    private func pruneObservations(_ observations: inout [ProcessCPUObservation], latestTimestamp: Date) {
        let cutoffTimestamp = latestTimestamp.addingTimeInterval(-Self.processWindowDuration)
        guard let lastBeforeWindowIndex = observations.lastIndex(where: { $0.timestamp < cutoffTimestamp }) else {
            return
        }

        if lastBeforeWindowIndex > 0 {
            observations.removeFirst(lastBeforeWindowIndex)
        }
    }

    private func cpuPercent(deltaCPUTime: UInt64, elapsed: TimeInterval) -> Double {
        (Double(deltaCPUTime) / Self.nanosecondsPerSecond) / elapsed * 100
    }

    private func shouldSendRepeatNotification(now: Date, lastAlertDate: Date?) -> Bool {
        guard let lastAlertDate else {
            return true
        }
        return now.timeIntervalSince(lastAlertDate) >= Self.repeatInterval
    }
}

private struct LoadMetrics {
    let latestSample: LoadSample?
    let recentAverage: Double?
    let baselineAverage: Double?
    let ratio: Double?
    let sampleCount: Int
    let powerSource: PowerSource
    let canEvaluate: Bool

    func meetsThreshold(thresholdRatio: Double, isAlreadyElevated: Bool) -> Bool {
        guard canEvaluate, let recentAverage, let ratio else {
            return false
        }

        if recentAverage < MonitorEngine.minimumRecentAverage {
            return false
        }

        return ratio >= (isAlreadyElevated ? MonitorEngine.clearRatio : thresholdRatio)
    }
}

private struct ProcessHistory {
    var name: String
    var observations: [ProcessCPUObservation]
}
