import Foundation
import IOKit.ps

protocol LoadAverageProvider {
    func currentLoadAverage() -> Double?
}

protocol PowerSourceProvider {
    func currentPowerSource() -> PowerSource
}

struct SystemLoadAverageProvider: LoadAverageProvider {
    func currentLoadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        let sampleCount = getloadavg(&loads, Int32(loads.count))
        guard sampleCount >= 3 else {
            return nil
        }
        return loads[2]
    }
}

struct SystemPowerSourceProvider: PowerSourceProvider {
    func currentPowerSource() -> PowerSource {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
        let batteryValue = kIOPSBatteryPowerValue as String
        let acValue = kIOPSACPowerValue as String

        switch source {
        case batteryValue:
            return .battery
        case acValue:
            return .ac
        default:
            return .unknown
        }
    }
}
