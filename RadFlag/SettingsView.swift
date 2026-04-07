import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Alert Threshold") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trigger ratio")
                        Spacer()
                        Text(String(format: "%.2fx", model.settings.thresholdRatio))
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { model.settings.thresholdRatio },
                            set: model.updateThresholdRatio
                        ),
                        in: 1.25...2.0,
                        step: 0.05
                    )

                    SettingsDescriptionText("Load alerts fire when the recent 5-minute average is at least this multiple of the baseline.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Process CPU")
                        Spacer()
                        Text(model.processThresholdText)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { model.settings.processCPUThresholdPercent },
                            set: model.updateProcessCPUThresholdPercent
                        ),
                        in: 50...400,
                        step: 10
                    )

                    SettingsDescriptionText("Process alerts fire when the top 5-minute-average process stays above this CPU level.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Adaptive Baseline") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Baseline rise")
                        Spacer()
                        Text(String(format: "%.2f", model.settings.baselineRiseFactor))
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { model.settings.baselineRiseFactor },
                            set: model.updateBaselineRiseFactor
                        ),
                        in: 0.01...0.10,
                        step: 0.01
                    )

                    SettingsDescriptionText("Higher values make the baseline climb faster when load stays elevated.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Baseline recovery")
                        Spacer()
                        Text(String(format: "%.2f", model.settings.baselineRecoveryFactor))
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { model.settings.baselineRecoveryFactor },
                            set: model.updateBaselineRecoveryFactor
                        ),
                        in: 0.03...0.30,
                        step: 0.01
                    )

                    SettingsDescriptionText("Higher values make the baseline fall faster after spikes; recovery is intentionally kept at least as fast as rise.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Behavior") {
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

            Section("Timing") {
                SettingsDescriptionText("Checks run every 20 seconds, process alerts evaluate a rolling 5-minute CPU window, repeated alerts are capped at every 5 minutes, and muting lasts 20 minutes.")
            }
        }
        .background(SettingsWindowFocusAccessor())
        .padding(20)
        .frame(width: 460)
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
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
