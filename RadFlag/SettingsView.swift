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

                    Text("Load alerts fire when the recent 5-minute average is at least this multiple of the baseline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                    Text("Process alerts fire when the top 5-minute-average process stays above this CPU level.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

                    Text("Higher values make the baseline climb faster when load stays elevated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                    Text("Higher values make the baseline fall faster after spikes; recovery is intentionally kept at least as fast as rise.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

                Text("Launch at login status: \(model.launchAtLoginStatus)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let launchAtLoginError = model.launchAtLoginError {
                    Text("Could not update login item: \(launchAtLoginError)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Timing") {
                Text("Checks run every 20 seconds, process alerts evaluate a rolling 5-minute CPU window, repeated alerts are capped at every 5 minutes, and muting lasts 20 minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
