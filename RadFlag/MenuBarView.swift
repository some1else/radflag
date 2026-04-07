import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(model.statusText, systemImage: model.statusSymbolName)
                    .font(.headline)
                    .foregroundStyle(model.snapshot.isElevated ? .red : .green)
                Spacer()
                Text("5m \(model.currentLoadText)")
                    .font(.headline.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Recent average", value: model.recentAverageText)
                LabeledContent("Baseline", value: model.baselineText)
                LabeledContent("Ratio", value: model.ratioText)
                HStack(alignment: .top, spacing: 8) {
                    Text("Top process")
                    Spacer(minLength: 8)
                    Text(model.topProcessNameText)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                LabeledContent("PID", value: model.topProcessPIDText)
                LabeledContent("5m CPU avg", value: model.topProcessCPUText)
                LabeledContent("Trigger", value: model.triggerReasonText)
                LabeledContent("Power", value: model.powerSourceText)
                LabeledContent("Last alert", value: model.lastAlertText)
            }
            .font(.system(size: 12))

            Text(model.warmupText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button(model.muteButtonTitle) {
                    model.toggleMute()
                }
                .disabled(!model.canToggleMute)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Button("Sample now") {
                    model.sampleNow()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320)
    }
}
