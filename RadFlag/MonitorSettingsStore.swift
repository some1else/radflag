import Foundation

final class MonitorSettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "radflag.monitor.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MonitorSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return MonitorSettings()
        }

        do {
            return try JSONDecoder().decode(MonitorSettings.self, from: data).normalized()
        } catch {
            return MonitorSettings()
        }
    }

    func save(_ settings: MonitorSettings) {
        let normalized = settings.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
