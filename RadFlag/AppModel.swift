import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot
    @Published private(set) var settings: MonitorSettings {
        didSet {
            settingsStore.save(settings)
        }
    }
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var launchAtLoginStatus: String = "Unknown"

    private let engine: MonitorEngine
    private let loadProvider: LoadAverageProvider
    private let powerProvider: PowerSourceProvider
    private let notificationCoordinator: NotificationCoordinating
    private let settingsStore: MonitorSettingsStore
    private var timer: Timer?

    init(
        engine: MonitorEngine = MonitorEngine(),
        loadProvider: LoadAverageProvider = SystemLoadAverageProvider(),
        powerProvider: PowerSourceProvider = SystemPowerSourceProvider(),
        notificationCoordinator: NotificationCoordinating? = nil,
        settingsStore: MonitorSettingsStore = MonitorSettingsStore()
    ) {
        self.engine = engine
        self.loadProvider = loadProvider
        self.powerProvider = powerProvider
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.snapshot = engine.snapshot
        self.notificationCoordinator = notificationCoordinator ?? NotificationCoordinator()

        self.notificationCoordinator.requestAuthorization()
        syncLaunchAtLogin(enabled: settings.launchAtLogin)
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    var menuBarTitle: String {
        "15m \(formattedNumber(snapshot.latestSample?.load15)) \(statusText)"
    }

    var statusText: String {
        snapshot.isElevated ? "HIGH" : "OK"
    }

    var statusSymbolName: String {
        snapshot.isElevated ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var currentLoadText: String {
        formattedNumber(snapshot.latestSample?.load15)
    }

    var recentAverageText: String {
        formattedNumber(snapshot.recentAverage)
    }

    var baselineText: String {
        formattedNumber(snapshot.baselineAverage)
    }

    var ratioText: String {
        guard let ratio = snapshot.ratio else {
            return "--"
        }
        return String(format: "%.2fx", ratio)
    }

    var powerSourceText: String {
        snapshot.latestSample?.powerSource.displayName ?? PowerSource.unknown.displayName
    }

    var lastAlertText: String {
        guard let lastAlertDate = snapshot.lastAlertDate else {
            return "Never"
        }

        return Self.timeFormatter.string(from: lastAlertDate)
    }

    var muteButtonTitle: String {
        isMuted ? "Unmute" : "Mute for 1 hour"
    }

    var canToggleMute: Bool {
        snapshot.isElevated || isMuted
    }

    var isMuted: Bool {
        if case .muted = snapshot.alertState {
            return true
        }
        return false
    }

    var warmupText: String {
        guard snapshot.isWarmingUp else {
            return "Monitoring with a 15-minute recent window against the prior 105 minutes."
        }

        let remainingSamples = max(0, MonitorEngine.minimumSampleCount - snapshot.sampleCount)
        return "Warming up baseline. \(remainingSamples) more minute sample(s) needed before alerts."
    }

    func updateThresholdRatio(_ ratio: Double) {
        settings.thresholdRatio = ratio
    }

    func updateSoundEnabled(_ isEnabled: Bool) {
        settings.soundEnabled = isEnabled
    }

    func updateLaunchAtLogin(_ isEnabled: Bool) {
        settings.launchAtLogin = isEnabled
        syncLaunchAtLogin(enabled: isEnabled)
    }

    func toggleMute() {
        if isMuted {
            snapshot = engine.unmute()
        } else {
            snapshot = engine.muteForOneHour()
        }
    }

    func sampleNow() {
        guard let load15 = loadProvider.currentLoadAverage() else {
            return
        }

        let update = engine.processSample(
            load15: load15,
            powerSource: powerProvider.currentPowerSource(),
            at: Date(),
            settings: settings
        )
        snapshot = update.snapshot

        if let notification = update.notification {
            notificationCoordinator.sendAlert(
                for: update.snapshot,
                kind: notification.kind,
                soundEnabled: settings.soundEnabled
            )
        }
    }

    private func startMonitoring() {
        sampleNow()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleNow()
            }
        }
        timer?.tolerance = 5
    }

    private func syncLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }

            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        launchAtLoginStatus = statusText(for: service.status)
    }

    private func statusText(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "Not found"
        case .notRegistered:
            return "Disabled"
        @unknown default:
            return "Unknown"
        }
    }

    private func formattedNumber(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.2f", value)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
