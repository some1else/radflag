import Foundation
import IOKit.ps

protocol LoadAverageProvider {
    func currentLoadAverage() -> Double?
}

protocol PowerSourceProvider {
    func currentPowerSource() -> PowerSource
}

protocol ProcessSnapshotProvider {
    func currentProcessSnapshots() -> [ProcessCPUSnapshot]
}

struct SystemLoadAverageProvider: LoadAverageProvider {
    func currentLoadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        let sampleCount = getloadavg(&loads, Int32(loads.count))
        guard sampleCount >= 3 else {
            return nil
        }
        return loads[1]
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

struct SystemProcessSnapshotProvider: ProcessSnapshotProvider {
    func currentProcessSnapshots() -> [ProcessCPUSnapshot] {
        let estimatedCount = max(Int(proc_listallpids(nil, 0)), 1)
        var pids = [pid_t](repeating: 0, count: estimatedCount)
        let discoveredCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard discoveredCount > 0 else {
            return []
        }

        return pids
            .prefix(Int(discoveredCount))
            .filter { $0 > 0 }
            .compactMap { pid in
                guard let totalCPUTime = totalCPUTime(for: pid) else {
                    return nil
                }

                return ProcessCPUSnapshot(
                    pid: pid,
                    name: processName(for: pid),
                    totalCPUTime: totalCPUTime
                )
            }
    }

    private func processName(for pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard length > 0 else {
            return "pid \(pid)"
        }
        return String(cString: nameBuffer)
    }

    private func totalCPUTime(for pid: pid_t) -> UInt64? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }

        guard result == 0 else {
            return nil
        }

        return info.ri_user_time + info.ri_system_time
    }
}
