import AppKit
import SwiftUI

private enum SettingsLayout {
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    static let descriptionLineSpacing: CGFloat = 3
    static let sliderGroupSpacing: CGFloat = 12
    static let sliderTextLeadingInset: CGFloat = 0
    static let sliderTrailingInset: CGFloat = 4
    static let contentPadding: CGFloat = 20
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                alertThresholdSection
                adaptiveBaselineSection
                behaviorSection
                timingSection
            }
            .padding(.horizontal, SettingsLayout.contentPadding)
            .padding(.top, SettingsLayout.contentPadding)
            .padding(.bottom, SettingsLayout.contentPadding + SettingsLayout.sectionSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SettingsWindowFocusAccessor())
        .frame(width: 460, height: 735)
    }

    private var alertThresholdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Alert Threshold")

            SettingsSliderGroup(
                title: "Trigger ratio",
                valueText: String(format: "%.2fx", model.settings.thresholdRatio),
                value: Binding(
                    get: { model.settings.thresholdRatio },
                    set: model.updateThresholdRatio
                ),
                range: 1.25...2.0,
                step: 0.05,
                description: "Load alerts fire when the recent \(model.loadWindowText) average is at least this multiple of the baseline.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Process CPU",
                valueText: model.processThresholdText,
                value: Binding(
                    get: { model.settings.processCPUThresholdPercent },
                    set: model.updateProcessCPUThresholdPercent
                ),
                range: 50...400,
                step: 10,
                description: "Process alerts fire when the top \(model.processWindowText) average process stays above this CPU level."
            )
        }
    }

    private var adaptiveBaselineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Adaptive Baseline", topSpacing: SettingsLayout.sectionSpacing)

            SettingsSliderGroup(
                title: "Baseline rise",
                valueText: String(format: "%.2f", model.settings.baselineRiseFactor),
                value: Binding(
                    get: { model.settings.baselineRiseFactor },
                    set: model.updateBaselineRiseFactor
                ),
                range: 0.01...0.10,
                step: 0.01,
                description: "Higher values make the baseline climb faster when load stays elevated.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Baseline recovery",
                valueText: String(format: "%.2f", model.settings.baselineRecoveryFactor),
                value: Binding(
                    get: { model.settings.baselineRecoveryFactor },
                    set: model.updateBaselineRecoveryFactor
                ),
                range: 0.03...0.30,
                step: 0.01,
                description: "Higher values make the baseline fall faster after spikes; recovery is intentionally kept at least as fast as rise."
            )
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Behavior", topSpacing: SettingsLayout.sectionSpacing)

            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                Toggle(
                    "Play notification sound",
                    isOn: Binding(
                        get: { model.settings.soundEnabled },
                        set: model.updateSoundEnabled
                    )
                )

                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: model.updateLaunchAtLogin
                    )
                )

                SettingsDescriptionText("Launch at login status: \(model.launchAtLoginStatus)")

                if let launchAtLoginError = model.launchAtLoginError {
                    SettingsDescriptionText("Could not update login item: \(launchAtLoginError)")
                }
            }
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Timing", topSpacing: SettingsLayout.sectionSpacing)

            SettingsSliderGroup(
                title: "Check interval",
                valueText: model.sampleIntervalText,
                value: Binding(
                    get: { model.settings.sampleIntervalSeconds },
                    set: model.updateSampleIntervalSeconds
                ),
                range: 10...60,
                step: 5,
                description: "Controls how often RadFlag samples load and process activity.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Load window",
                valueText: model.loadWindowShortText,
                value: Binding(
                    get: { model.settings.loadWindowSeconds },
                    set: model.updateLoadWindowSeconds
                ),
                range: 120...900,
                step: 60,
                description: "Controls how much recent load history is averaged for the load rule.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Process window",
                valueText: shortMinutes(model.settings.processWindowSeconds),
                value: Binding(
                    get: { model.settings.processWindowSeconds },
                    set: model.updateProcessWindowSeconds
                ),
                range: 120...900,
                step: 60,
                description: "Controls how long a process must sustain CPU usage before it trips the process rule.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Repeat alerts",
                valueText: shortMinutes(model.settings.repeatIntervalSeconds),
                value: Binding(
                    get: { model.settings.repeatIntervalSeconds },
                    set: model.updateRepeatIntervalSeconds
                ),
                range: 60...1800,
                step: 60,
                description: "Sets the minimum gap between repeated notifications while the system stays elevated.",
                showsBottomPadding: true
            )

            SettingsSliderGroup(
                title: "Mute duration",
                valueText: shortMinutes(model.settings.muteIntervalSeconds),
                value: Binding(
                    get: { model.settings.muteIntervalSeconds },
                    set: model.updateMuteIntervalSeconds
                ),
                range: 300...3600,
                step: 300,
                description: "Controls how long manual muting suppresses notifications."
            )
        }
    }

    private func shortMinutes(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }

        return "\(Int(seconds / 60))m"
    }
}

private struct SettingsSliderGroup: View {
    let title: String
    let valueText: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let description: String
    var showsBottomPadding = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
            }
            .padding(.leading, SettingsLayout.sliderTextLeadingInset)

            Slider(value: value, in: range, step: step)

            SettingsDescriptionText(description)
                .padding(.leading, SettingsLayout.sliderTextLeadingInset)
                .padding(.trailing, SettingsLayout.sliderTrailingInset)
        }
        .padding(.bottom, showsBottomPadding ? SettingsLayout.sliderGroupSpacing : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDescriptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(SettingsLayout.descriptionLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSectionHeader: View {
    let title: String
    var topSpacing: CGFloat = 0

    init(_ title: String, topSpacing: CGFloat = 0) {
        self.title = title
        self.topSpacing = topSpacing
    }

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .textCase(nil)
            .foregroundStyle(.primary.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topSpacing)
            .padding(.bottom, SettingsLayout.rowSpacing)
    }
}

private struct SettingsWindowFocusAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        FocusNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class FocusNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
}
