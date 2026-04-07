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
    private let processSnapshotProvider: ProcessSnapshotProvider
    private let notificationCoordinator: NotificationCoordinating
    private let settingsStore: MonitorSettingsStore
    private var timer: Timer?

    init(
        engine: MonitorEngine = MonitorEngine(),
        loadProvider: LoadAverageProvider = SystemLoadAverageProvider(),
        powerProvider: PowerSourceProvider = SystemPowerSourceProvider(),
        processSnapshotProvider: ProcessSnapshotProvider = SystemProcessSnapshotProvider(),
        notificationCoordinator: NotificationCoordinating? = nil,
        settingsStore: MonitorSettingsStore = MonitorSettingsStore()
    ) {
        self.engine = engine
        self.loadProvider = loadProvider
        self.powerProvider = powerProvider
        self.processSnapshotProvider = processSnapshotProvider
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
        "5m \(formattedNumber(snapshot.latestSample?.loadAverage)) \(statusText)"
    }

    var statusText: String {
        snapshot.isElevated ? "HIGH" : "OK"
    }

    var statusSymbolName: String {
        snapshot.isElevated ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var currentLoadText: String {
        formattedNumber(snapshot.latestSample?.loadAverage)
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

    var processThresholdText: String {
        String(format: "%.0f%%", settings.processCPUThresholdPercent)
    }

    var powerSourceText: String {
        snapshot.latestSample?.powerSource.displayName ?? PowerSource.unknown.displayName
    }

    var triggerReasonText: String {
        snapshot.triggerReason?.displayName ?? "--"
    }

    var topProcessNameText: String {
        snapshot.topProcess?.name ?? "--"
    }

    var topProcessPIDText: String {
        guard let topProcess = snapshot.topProcess else {
            return "--"
        }
        return String(Int32(topProcess.pid))
    }

    var topProcessCPUText: String {
        guard let offender = snapshot.topProcess else {
            return "--"
        }
        return String(format: "%.0f%%", offender.averageCPUPercent)
    }

    var lastAlertText: String {
        guard let lastAlertDate = snapshot.lastAlertDate else {
            return "Never"
        }

        return Self.timeFormatter.string(from: lastAlertDate)
    }

    var muteButtonTitle: String {
        isMuted ? "Unmute" : "Mute for 20 minutes"
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

    var monitoringStatusRows: [MonitoringStatusRow] {
        Self.makeMonitoringStatusRows(snapshot: snapshot, processThresholdText: processThresholdText)
    }

    static func makeMonitoringStatusRows(
        snapshot: MonitorSnapshot,
        processThresholdText: String
    ) -> [MonitoringStatusRow] {
        var rows = [MonitoringStatusRow(label: "Window:", value: "5 min")]

        guard snapshot.isWarmingUp else {
            rows.append(MonitoringStatusRow(label: "Load rule:", value: "Adaptive baseline"))
            rows.append(MonitoringStatusRow(label: "Baseline:", value: "Slow rise / fast recovery"))
            rows.append(MonitoringStatusRow(label: "Process rule:", value: "5m CPU average"))
            rows.append(MonitoringStatusRow(label: "Threshold:", value: "> \(processThresholdText)"))
            rows.append(MonitoringStatusRow(label: "Alerts:", value: "Battery only"))
            return rows
        }

        let remainingProcessSamples = max(0, MonitorEngine.minimumProcessSampleCount - snapshot.sampleCount)
        let remainingLoadSamples = max(0, MonitorEngine.minimumSampleCount - snapshot.sampleCount)

        if remainingProcessSamples > 0 {
            rows.append(
                MonitoringStatusRow(
                    label: "Process rule:",
                    value: "Arms in \(remainingProcessSamples) sample(s)"
                )
            )
            rows.append(
                MonitoringStatusRow(
                    label: "Load rule:",
                    value: "Warms in \(remainingLoadSamples) sample(s)"
                )
            )
            rows.append(MonitoringStatusRow(label: "Alerts:", value: "Battery only"))
            return rows
        }

        rows.append(
            MonitoringStatusRow(
                label: "Process rule:",
                value: "Live (> \(processThresholdText))"
            )
        )
        rows.append(
            MonitoringStatusRow(
                label: "Load rule:",
                value: "Warms in \(remainingLoadSamples) sample(s)"
            )
        )
        rows.append(MonitoringStatusRow(label: "Alerts:", value: "Battery only"))
        return rows
    }

    func updateThresholdRatio(_ ratio: Double) {
        updateSettings { $0.thresholdRatio = ratio }
    }

    func updateProcessCPUThresholdPercent(_ threshold: Double) {
        updateSettings { $0.processCPUThresholdPercent = threshold }
    }

    func updateBaselineRiseFactor(_ factor: Double) {
        updateSettings { $0.baselineRiseFactor = factor }
    }

    func updateBaselineRecoveryFactor(_ factor: Double) {
        updateSettings { $0.baselineRecoveryFactor = factor }
    }

    func updateSoundEnabled(_ isEnabled: Bool) {
        updateSettings { $0.soundEnabled = isEnabled }
    }

    func updateLaunchAtLogin(_ isEnabled: Bool) {
        updateSettings { $0.launchAtLogin = isEnabled }
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
        guard let loadAverage = loadProvider.currentLoadAverage() else {
            return
        }

        let update = engine.processSample(
            loadAverage: loadAverage,
            powerSource: powerProvider.currentPowerSource(),
            processSnapshots: processSnapshotProvider.currentProcessSnapshots(),
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
        timer = Timer.scheduledTimer(withTimeInterval: MonitorEngine.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleNow()
            }
        }
        timer?.tolerance = 2
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

    private func updateSettings(_ mutate: (inout MonitorSettings) -> Void) {
        var nextSettings = settings
        mutate(&nextSettings)
        nextSettings.enforceBaselineFactorOrder()
        settings = nextSettings
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
