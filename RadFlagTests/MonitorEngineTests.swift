import Foundation
import XCTest
@testable import RadFlag

final class MonitorEngineTests: XCTestCase {
    func testRollingBaselineExcludesMostRecentFifteenSamples() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)

        for minute in 0..<105 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            _ = engine.processSample(load15: 1.0, powerSource: .battery, at: date, settings: settings)
        }

        for minute in 105..<120 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            _ = engine.processSample(load15: 4.0, powerSource: .battery, at: date, settings: settings)
        }

        XCTAssertEqual(try XCTUnwrap(engine.snapshot.recentAverage), 4.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.snapshot.baselineAverage), 1.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.snapshot.ratio), 4.0, accuracy: 0.0001)
    }

    func testWarmupPreventsAlertsBeforeThirtySamples() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?

        for minute in 0..<29 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            lastUpdate = engine.processSample(load15: 3.0, powerSource: .battery, at: date, settings: settings)
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .ok)
        XCTAssertTrue(lastUpdate?.snapshot.isWarmingUp ?? false)
        XCTAssertNil(lastUpdate?.notification)
    }

    func testEnteringHighStateAndRepeatingAfterFifteenMinutes() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?
        var sawEnteredHigh = false
        var sawRepeatedHigh = false

        for minute in 0..<30 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            lastUpdate = engine.processSample(load15: 1.0, powerSource: .battery, at: date, settings: settings)
        }

        for minute in 30..<45 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            lastUpdate = engine.processSample(load15: 3.0, powerSource: .battery, at: date, settings: settings)
            if lastUpdate?.notification?.kind == .enteredHigh {
                sawEnteredHigh = true
            }
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertTrue(sawEnteredHigh)

        for minute in 45..<60 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            lastUpdate = engine.processSample(load15: 4.0, powerSource: .battery, at: date, settings: settings)
            if lastUpdate?.notification?.kind == .repeatedHigh {
                sawRepeatedHigh = true
            }
        }

        XCTAssertEqual(lastUpdate?.snapshot.alertState, .high)
        XCTAssertTrue(sawRepeatedHigh)
    }

    func testMuteSuppressesRepeatsUntilExpiry() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)
        var lastUpdate: MonitorUpdate?
        var sawEnteredHigh = false

        for minute in 0..<30 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            _ = engine.processSample(load15: 1.0, powerSource: .battery, at: date, settings: settings)
        }

        for minute in 30..<45 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            lastUpdate = engine.processSample(load15: 3.0, powerSource: .battery, at: date, settings: settings)
            if lastUpdate?.notification?.kind == .enteredHigh {
                sawEnteredHigh = true
            }
        }

        XCTAssertTrue(sawEnteredHigh)

        let muteDate = start.addingTimeInterval(TimeInterval(45 * 60))
        _ = engine.muteForOneHour(at: muteDate)
        XCTAssertEqual(engine.snapshot.alertState, .muted(until: muteDate.addingTimeInterval(MonitorEngine.muteInterval)))

        for minute in 45..<105 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            let load: Double
            switch minute {
            case 45..<60:
                load = 4.0
            case 60..<75:
                load = 5.0
            case 75..<90:
                load = 6.0
            default:
                load = 7.0
            }
            lastUpdate = engine.processSample(load15: load, powerSource: .battery, at: date, settings: settings)
        }

        XCTAssertNil(lastUpdate?.notification)
        XCTAssertTrue(lastUpdate?.snapshot.isElevated ?? false)

        let expiryUpdate = engine.processSample(
            load15: 8.0,
            powerSource: .battery,
            at: start.addingTimeInterval(TimeInterval(105 * 60)),
            settings: settings
        )

        XCTAssertEqual(expiryUpdate.notification?.kind, .repeatedHigh)
        XCTAssertEqual(expiryUpdate.snapshot.alertState, .high)
    }

    func testPowerSourceGateKeepsSamplingButClearsAlertOffBattery() {
        let engine = MonitorEngine()
        let settings = MonitorSettings()
        let start = Date(timeIntervalSince1970: 0)

        for minute in 0..<30 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            _ = engine.processSample(load15: 1.0, powerSource: .battery, at: date, settings: settings)
        }

        for minute in 30..<45 {
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            _ = engine.processSample(load15: 4.0, powerSource: .battery, at: date, settings: settings)
        }

        let acUpdate = engine.processSample(
            load15: 5.0,
            powerSource: .ac,
            at: start.addingTimeInterval(TimeInterval(45 * 60)),
            settings: settings
        )

        XCTAssertEqual(acUpdate.snapshot.alertState, .ok)
        XCTAssertEqual(acUpdate.snapshot.sampleCount, 46)
        XCTAssertEqual(acUpdate.snapshot.latestSample?.powerSource, .ac)
    }
}
