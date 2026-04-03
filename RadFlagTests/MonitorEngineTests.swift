import Foundation
import XCTest
@testable import RadFlag

final class MonitorEngineTests: XCTestCase {
    func testRollingBaselineExcludesMostRecentFifteenSamples() throws {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)

        for sampleIndex in 0..<105 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 1.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        for sampleIndex in 105..<120 {
            _ = sample(
                engine,
                sampleIndex: sampleIndex,
                loadAverage: 4.0,
                processSnapshots: [],
                start: start,
                settings: settings
            )
        }

        XCTAssertEqual(try XCTUnwrap(engine.snapshot.recentAverage), 4.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.snapshot.baselineAverage), 1.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.snapshot.ratio), 4.0, accuracy: 0.0001)
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
        XCTAssertEqual(triggerUpdate.snapshot.processOffender?.pid, pid)
        XCTAssertEqual(triggerUpdate.snapshot.processOffender?.name, "Code Helper")
        XCTAssertEqual(try XCTUnwrap(triggerUpdate.snapshot.processOffender?.averageCPUPercent), 150, accuracy: 0.0001)
        XCTAssertTrue(triggerUpdate.snapshot.isWarmingUp)
        XCTAssertEqual(triggerUpdate.notification?.kind, .enteredHigh)
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
        XCTAssertEqual(lastUpdate?.snapshot.processOffender?.pid, fasterPID)
        XCTAssertEqual(lastUpdate?.snapshot.processOffender?.name, "TypeScript Server")
        XCTAssertEqual(try XCTUnwrap(lastUpdate?.snapshot.processOffender?.averageCPUPercent), 180, accuracy: 0.0001)
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
        XCTAssertNil(clearedUpdate.snapshot.processOffender)
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

    private func cumulativeCPUTime(sampleIndex: Int, cpuPercent: Double) -> UInt64 {
        UInt64(Double(sampleIndex) * MonitorEngine.sampleInterval * cpuPercent / 100 * 1_000_000_000)
    }
}
