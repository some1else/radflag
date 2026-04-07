import Foundation
import XCTest
@testable import RadFlag

final class MonitorEngineTests: XCTestCase {
    func testAdaptiveBaselineSeedsAfterFirstFullRecentWindow() throws {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)

        for sampleIndex in 0..<14 {
            let update = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 2.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )

            XCTAssertNil(update.snapshot.recentAverage)
            XCTAssertNil(update.snapshot.baselineAverage)
            XCTAssertNil(update.snapshot.ratio)
        }

        let seedUpdate = sample(
            engine,
            sampleIndex: 14,
            loadAverage: 2.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )

        XCTAssertEqual(try XCTUnwrap(seedUpdate.snapshot.recentAverage), 2.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(seedUpdate.snapshot.baselineAverage), 2.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(seedUpdate.snapshot.ratio), 1.0, accuracy: 0.0001)
    }

    func testAdaptiveBaselineRiseAndRecoveryUseSeparateFactors() throws {
        let engine = MonitorEngine()
        var settings = MonitorSettings()
        settings.baselineRiseFactor = 0.03
        settings.baselineRecoveryFactor = 0.10
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<15 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 15..<30 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        let riseBaselineBefore = try XCTUnwrap(lastUpdate?.snapshot.baselineAverage)
        let riseStepUpdate = sample(
            engine,
            sampleIndex: 30,
            loadAverage: 3.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )
        let riseBaselineAfter = try XCTUnwrap(riseStepUpdate.snapshot.baselineAverage)
        XCTAssertEqual(try XCTUnwrap(riseStepUpdate.snapshot.recentAverage), 3.0, accuracy: 0.0001)
        let riseFraction = (riseBaselineAfter - riseBaselineBefore) / (3.0 - riseBaselineBefore)

        for sampleIndex in 31..<46 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        let recoveryBaselineBefore = try XCTUnwrap(lastUpdate?.snapshot.baselineAverage)
        let recoveryStepUpdate = sample(
            engine,
            sampleIndex: 46,
            loadAverage: 1.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )
        let recoveryBaselineAfter = try XCTUnwrap(recoveryStepUpdate.snapshot.baselineAverage)
        XCTAssertEqual(try XCTUnwrap(recoveryStepUpdate.snapshot.recentAverage), 1.0, accuracy: 0.0001)
        let recoveryFraction = (recoveryBaselineBefore - recoveryBaselineAfter) / (recoveryBaselineBefore - 1.0)

        XCTAssertEqual(riseFraction, settings.baselineRiseFactor, accuracy: 0.0001)
        XCTAssertEqual(recoveryFraction, settings.baselineRecoveryFactor, accuracy: 0.0001)
        XCTAssertGreaterThan(recoveryFraction, riseFraction)
    }

    func testUpdatingBaselineFactorsAffectsFutureStepsWithoutReset() throws {
        let engine = MonitorEngine()
        var settings = MonitorSettings()
        settings.baselineRiseFactor = 0.01
        settings.baselineRecoveryFactor = 0.10
        let start = Date(timeIntervalSince1970: 0)

        for sampleIndex in 0..<15 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 15..<30 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        let beforeFactorChange = sample(
            engine,
            sampleIndex: 30,
            loadAverage: 3.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )
        let baselineBefore = try XCTUnwrap(beforeFactorChange.snapshot.baselineAverage)

        settings.baselineRiseFactor = 0.10
        settings.baselineRecoveryFactor = 0.10

        let afterFactorChange = sample(
            engine,
            sampleIndex: 31,
            loadAverage: 3.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )
        let baselineAfter = try XCTUnwrap(afterFactorChange.snapshot.baselineAverage)
        let expected = baselineBefore + settings.baselineRiseFactor * (3.0 - baselineBefore)

        XCTAssertEqual(try XCTUnwrap(afterFactorChange.snapshot.recentAverage), 3.0, accuracy: 0.0001)
        XCTAssertGreaterThan(baselineBefore, 1.0)
        XCTAssertEqual(baselineAfter, expected, accuracy: 0.0001)
    }

    func testWarmupPreventsLoadAlertsBeforeThirtySamples() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<29 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .ok)
        XCTAssertTrue(lastUpdate?.snapshot.isWarmingUp ?? false)
        XCTAssertNil(lastUpdate?.notification)
    }

    func testEnteringHighStateAndRepeatingAfterFiveMinutes() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?
        var sawEnteredHigh = false
        var sawRepeatedHigh = false

        for sampleIndex in 0..<30 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 30..<45 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
            if lastUpdate?.notification?.kind == .enteredHigh {
                sawEnteredHigh = true
            }
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertEqual(lastUpdate?.snapshot.triggerReason, .load)
        XCTAssertTrue(sawEnteredHigh)

        for sampleIndex in 45..<60 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 4.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
            if lastUpdate?.notification?.kind == .repeatedHigh {
                sawRepeatedHigh = true
            }
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertEqual(lastUpdate?.snapshot.triggerReason, .load)
        XCTAssertTrue(sawRepeatedHigh)
    }

    func testProcessTripwireNeedsFullFiveMinutesAndTriggersWithoutLoadSpike() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 4242
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<(MonitorEngine.minimumProcessSampleCount - 1) {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 150)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .ok)
        XCTAssertNil(lastUpdate?.snapshot.topProcess)
        XCTAssertNil(lastUpdate?.snapshot.processOffender)

        let triggerUpdate = sample(
            engine,
            sampleIndex: MonitorEngine.minimumProcessSampleCount - 1,
            loadAverage: 1.0,
            processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: MonitorEngine.minimumProcessSampleCount - 1, cpuPercent: 150)],
            start: start,
            settings: settings
        )

        XCTAssertEqual(triggerUpdate.snapshot.alertState, .high)
        XCTAssertEqual(triggerUpdate.snapshot.triggerReason, .process)
        XCTAssertEqual(triggerUpdate.snapshot.topProcess?.pid, pid)
        XCTAssertEqual(triggerUpdate.snapshot.processOffender?.pid, pid)
        XCTAssertEqual(triggerUpdate.snapshot.processOffender?.name, "Code Helper")
        XCTAssertEqual(try XCTUnwrap(triggerUpdate.snapshot.processOffender?.averageCPUPercent), 150, accuracy: 0.0001)
        XCTAssertTrue(triggerUpdate.snapshot.isWarmingUp)
        XCTAssertEqual(triggerUpdate.notification?.kind, .enteredHigh)
    }

    func testWholeWindowDeltaMathReportsConstantFiveMinuteAverage() throws {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 5050
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Renderer", sampleIndex: sampleIndex, cpuPercent: 50)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(try XCTUnwrap(lastUpdate?.snapshot.topProcess?.averageCPUPercent), 50, accuracy: 0.0001)
        XCTAssertNil(lastUpdate?.snapshot.processOffender)
    }

    func testWholeWindowDeltaMathUsesElapsedTimeForIrregularIntervals() throws {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 5151
        let offsets: [TimeInterval] = [0, 10, 70, 130, 190, 250, 310]
        let intervalCPUPercentages: [Double] = [10, 90, 10, 90, 10, 90]
        var lastUpdate: MonitorUpdate?

        for (index, offset) in offsets.enumerated() {
            lastUpdate = sampleAt(
                engine,
                at: start.addingTimeInterval(offset),
                loadAverage: 1.0,
                processSnapshots: [
                    processSnapshot(
                        pid: pid,
                        name: "TypeScript Server",
                        totalCPUTime: cumulativeCPUTime(
                            offsets: offsets,
                            cpuPercentages: intervalCPUPercentages,
                            throughObservation: index
                        )
                    )
                ],
                settings: settings
            )
        }

        XCTAssertEqual(try XCTUnwrap(lastUpdate?.snapshot.topProcess?.averageCPUPercent), 58.0, accuracy: 0.001)
        XCTAssertNil(lastUpdate?.snapshot.processOffender)
    }

    func testProcessWarmupRequiresFiveMinutesOfElapsedTimeNotJustSampleCount() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 6262
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            lastUpdate = sampleAt(
                engine,
                at: start.addingTimeInterval(Double(sampleIndex) * 10),
                loadAverage: 1.0,
                processSnapshots: [
                    processSnapshot(
                        pid: pid,
                        name: "Code Helper",
                        totalCPUTime: UInt64(Double(sampleIndex) * 10 * 1.5 * 1_000_000_000)
                    )
                ],
                settings: settings
            )
        }

        XCTAssertNil(lastUpdate?.snapshot.topProcess)
        XCTAssertNil(lastUpdate?.snapshot.processOffender)
        XCTAssertEqual(lastUpdate?.snapshot.alertState, .ok)
    }

    func testTopProcessAppearsBeforeCrossingConfiguredThreshold() throws {
        let engine = MonitorEngine()
        var settings = MonitorSettings()
        settings.processCPUThresholdPercent = 200
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 8080
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 150)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .ok)
        XCTAssertEqual(lastUpdate?.snapshot.topProcess?.pid, pid)
        XCTAssertEqual(lastUpdate?.snapshot.topProcess?.name, "Code Helper")
        XCTAssertEqual(try XCTUnwrap(lastUpdate?.snapshot.topProcess?.averageCPUPercent), 150, accuracy: 0.0001)
        XCTAssertNil(lastUpdate?.snapshot.processOffender)
        XCTAssertNil(lastUpdate?.snapshot.triggerReason)
    }

    func testHighestProcessOffenderWins() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let slowerPID: pid_t = 111
        let fasterPID: pid_t = 222
        var lastUpdate: MonitorUpdate?

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [
                    processSnapshot(pid: slowerPID, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 130),
                    processSnapshot(pid: fasterPID, name: "TypeScript Server", sampleIndex: sampleIndex, cpuPercent: 180),
                ],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertEqual(lastUpdate?.snapshot.triggerReason, .process)
        XCTAssertEqual(lastUpdate?.snapshot.topProcess?.pid, fasterPID)
        XCTAssertEqual(lastUpdate?.snapshot.topProcess?.name, "TypeScript Server")
        XCTAssertEqual(lastUpdate?.snapshot.processOffender?.pid, fasterPID)
        XCTAssertEqual(lastUpdate?.snapshot.processOffender?.name, "TypeScript Server")
        XCTAssertEqual(try XCTUnwrap(lastUpdate?.snapshot.processOffender?.averageCPUPercent), 180, accuracy: 0.0001)
    }

    func testConfigurableProcessThresholdChangesOnlyProcessAlerting() {
        let engine = MonitorEngine()
        var settings = MonitorSettings()
        settings.processCPUThresholdPercent = 160
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 9090

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 150)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(engine.snapshot.alertState, .ok)
        XCTAssertEqual(engine.snapshot.topProcess?.pid, pid)
        XCTAssertNil(engine.snapshot.processOffender)

        settings.processCPUThresholdPercent = 140
        let processTriggerUpdate = sample(
            engine,
            sampleIndex: MonitorEngine.minimumProcessSampleCount,
            loadAverage: 1.0,
            processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: MonitorEngine.minimumProcessSampleCount, cpuPercent: 150)],
            start: start,
            settings: settings
        )

        XCTAssertEqual(processTriggerUpdate.snapshot.alertState, .high)
        XCTAssertEqual(processTriggerUpdate.snapshot.triggerReason, .process)
        XCTAssertEqual(processTriggerUpdate.snapshot.processOffender?.pid, pid)

        let loadOnlyEngine = MonitorEngine()
        var loadOnlySettings = MonitorSettings()
        loadOnlySettings.processCPUThresholdPercent = 400

        for sampleIndex in 0..<30 {
            _ = sample(
                loadOnlyEngine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: loadOnlySettings
            )
        }

        var loadAlert: MonitorUpdate?
        for sampleIndex in 30..<45 {
            loadAlert = sample(
                loadOnlyEngine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: loadOnlySettings
            )
        }

        XCTAssertEqual(loadAlert?.snapshot.alertState, .high)
        XCTAssertEqual(loadAlert?.snapshot.triggerReason, .load)
    }

    func testExitedProcessIsPrunedAndAlertClears() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 5150

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Renderer", sampleIndex: sampleIndex, cpuPercent: 160)],
                start: start,
                settings: settings
            )
        }

        let clearedUpdate = sample(
            engine,
            sampleIndex: MonitorEngine.minimumProcessSampleCount,
            loadAverage: 1.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )

        XCTAssertEqual(clearedUpdate.snapshot.alertState, .ok)
        XCTAssertNil(clearedUpdate.snapshot.triggerReason)
        XCTAssertNil(clearedUpdate.snapshot.topProcess)
        XCTAssertNil(clearedUpdate.snapshot.processOffender)
    }

    func testProcessHistoryResetsWhenCumulativeCPUTimeGoesBackwards() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 7171

        for sampleIndex in 0..<MonitorEngine.minimumProcessSampleCount {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Renderer", sampleIndex: sampleIndex, cpuPercent: 160)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(engine.snapshot.processOffender?.pid, pid)

        let resetUpdate = sampleAt(
            engine,
            at: start.addingTimeInterval(Double(MonitorEngine.minimumProcessSampleCount) * MonitorEngine.sampleInterval),
            loadAverage: 1.0,
            processSnapshots: [processSnapshot(pid: pid, name: "Renderer", totalCPUTime: 1)],
            settings: settings
        )

        XCTAssertNil(resetUpdate.snapshot.topProcess)
        XCTAssertNil(resetUpdate.snapshot.processOffender)
        XCTAssertEqual(resetUpdate.snapshot.alertState, .ok)
    }

    func testHighStaysWhileEitherRuleIsStillActive() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        let pid: pid_t = 6060
        var lastUpdate: MonitorUpdate?
        var sawCombinedReason = false

        for sampleIndex in 0..<30 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 140)],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 30..<45 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 4.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 140)],
                start: start,
                settings: settings
            )
            if lastUpdate?.snapshot.triggerReason == .loadAndProcess {
                sawCombinedReason = true
            }
        }

        XCTAssertTrue(sawCombinedReason)

        for sampleIndex in 45..<60 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [processSnapshot(pid: pid, name: "Code Helper", sampleIndex: sampleIndex, cpuPercent: 140)],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertEqual(lastUpdate?.snapshot.triggerReason, .process)

        let clearedUpdate = sample(
            engine,
            sampleIndex: 60,
            loadAverage: 1.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )

        XCTAssertEqual(clearedUpdate.snapshot.alertState, .ok)
        XCTAssertNil(clearedUpdate.snapshot.triggerReason)
    }

    func testMuteSuppressesRepeatsUntilExpiry() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?
        var sawEnteredHigh = false

        for sampleIndex in 0..<30 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 30..<45 {
            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 3.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
            if lastUpdate?.notification?.kind == .enteredHigh {
                sawEnteredHigh = true
            }
        }

        XCTAssertTrue(sawEnteredHigh)

        let muteDate = date(for: 45, from: start)
        _ = engine.muteForOneHour(at: muteDate)
        XCTAssertEqual(engine.snapshot.alertState, .muted(until: muteDate.addingTimeInterval(MonitorEngine.muteInterval)))

        for sampleIndex in 45..<105 {
            let loadAverage: Double
            switch sampleIndex {
            case 45..<60:
                loadAverage = 4.0
            case 60..<75:
                loadAverage = 5.0
            case 75..<90:
                loadAverage = 6.0
            default:
                loadAverage = 7.0
            }

            lastUpdate = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: loadAverage,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        XCTAssertNil(lastUpdate?.notification)
        XCTAssertTrue(lastUpdate?.snapshot.isElevated ?? false)

        let expiryUpdate = sample(
            engine,
            sampleIndex: 105,
            loadAverage: 8.0,
            processSnapshots: [],
            start: start,
            settings: settings
        )

        XCTAssertEqual(expiryUpdate.notification?.kind, .repeatedHigh)
        XCTAssertEqual(expiryUpdate.snapshot.alertState, .high)
    }

    func testPowerSourceGateKeepsSamplingButClearsAlertOffBattery() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)

        for sampleIndex in 0..<30 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 30..<45 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 4.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        let acUpdate = sample(
            engine,
            sampleIndex: 45,
            loadAverage: 5.0,
            powerSource: .ac,
            processSnapshots: [],
            start: start,
            settings: settings
        )

        XCTAssertEqual(acUpdate.snapshot.alertState, .ok)
        XCTAssertEqual(acUpdate.snapshot.sampleCount, 46)
        XCTAssertEqual(acUpdate.snapshot.latestSample?.powerSource, .ac)
    }

    private func sample(
        _ engine: MonitorEngine,
        sampleIndex: Int,
        loadAverage: Double,
        powerSource: PowerSource = .battery,
        processSnapshots: [ProcessCPUSnapshot],
        start: Date,
        settings: MonitorSettings
    ) -> MonitorUpdate {
        engine.processSample(
            loadAverage: loadAverage,
            powerSource: powerSource,
            processSnapshots: processSnapshots,
            at: date(for: sampleIndex, from: start),
            settings: settings
        )
    }

    private func sampleAt(
        _ engine: MonitorEngine,
        at date: Date,
        loadAverage: Double,
        powerSource: PowerSource = .battery,
        processSnapshots: [ProcessCPUSnapshot],
        settings: MonitorSettings
    ) -> MonitorUpdate {
        engine.processSample(
            loadAverage: loadAverage,
            powerSource: powerSource,
            processSnapshots: processSnapshots,
            at: date,
            settings: settings
        )
    }

    private func date(for sampleIndex: Int, from start: Date) -> Date {
        start.addingTimeInterval(Double(sampleIndex) * MonitorEngine.sampleInterval)
    }

    private func processSnapshot(pid: pid_t, name: String, sampleIndex: Int, cpuPercent: Double) -> ProcessCPUSnapshot {
        ProcessCPUSnapshot(
            pid: pid,
            name: name,
            totalCPUTime: cumulativeCPUTime(sampleIndex: sampleIndex, cpuPercent: cpuPercent)
        )
    }

    private func processSnapshot(pid: pid_t, name: String, totalCPUTime: UInt64) -> ProcessCPUSnapshot {
        ProcessCPUSnapshot(pid: pid, name: name, totalCPUTime: totalCPUTime)
    }

    private func cumulativeCPUTime(sampleIndex: Int, cpuPercent: Double) -> UInt64 {
        UInt64(Double(sampleIndex) * MonitorEngine.sampleInterval * cpuPercent / 100 * 1_000_000_000)
    }

    private func cumulativeCPUTime(
        offsets: [TimeInterval],
        cpuPercentages: [Double],
        throughObservation observationIndex: Int
    ) -> UInt64 {
        guard observationIndex > 0 else {
            return 0
        }

        let cpuTime = zip(offsets.dropFirst().prefix(observationIndex), cpuPercentages.prefix(observationIndex))
            .enumerated()
            .reduce(0.0) { partialResult, element in
                let (index, (endOffset, cpuPercent)) = element
                let startOffset = offsets[index]
                let elapsed = endOffset - startOffset
                return partialResult + (elapsed * cpuPercent / 100)
            }

        return UInt64(cpuTime * 1_000_000_000)
    }
}

final class MonitorSettingsStoreTests: XCTestCase {
    func testStoreDefaultsIncludeProcessCPUThreshold() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MonitorSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load().processCPUThresholdPercent, 100)
        XCTAssertEqual(store.load().baselineRiseFactor, 0.03, accuracy: 0.0001)
        XCTAssertEqual(store.load().baselineRecoveryFactor, 0.10, accuracy: 0.0001)
    }

    func testStorePersistsProcessCPUThreshold() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MonitorSettingsStore(defaults: defaults)
        var settings = MonitorSettings()
        settings.thresholdRatio = 1.7
        settings.processCPUThresholdPercent = 230
        settings.soundEnabled = false
        settings.launchAtLogin = false

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testLegacySettingsJSONDecodesAdaptiveDefaults() throws {
        let legacyData = """
        {
          "thresholdRatio": 1.7,
          "processCPUThresholdPercent": 230,
          "soundEnabled": false,
          "launchAtLogin": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MonitorSettings.self, from: legacyData)

        XCTAssertEqual(decoded.thresholdRatio, 1.7, accuracy: 0.0001)
        XCTAssertEqual(decoded.processCPUThresholdPercent, 230, accuracy: 0.0001)
        XCTAssertFalse(decoded.soundEnabled)
        XCTAssertFalse(decoded.launchAtLogin)
        XCTAssertEqual(decoded.baselineRiseFactor, 0.03, accuracy: 0.0001)
        XCTAssertEqual(decoded.baselineRecoveryFactor, 0.10, accuracy: 0.0001)
    }

    func testStoreNormalizesBaselineRecoveryNotBelowRise() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MonitorSettingsStore(defaults: defaults)
        var settings = MonitorSettings()
        settings.baselineRiseFactor = 0.08
        settings.baselineRecoveryFactor = 0.04

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.baselineRiseFactor, 0.08, accuracy: 0.0001)
        XCTAssertEqual(loaded.baselineRecoveryFactor, 0.08, accuracy: 0.0001)
    }
}
