import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

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
                LabeledContent("Trigger", value: model.triggerReasonText)
                if model.hasProcessOffender {
                    LabeledContent("Offender", value: model.offenderText)
                    LabeledContent("CPU avg", value: model.offenderCPUText)
                }
                LabeledContent("Power", value: model.powerSourceText)
                LabeledContent("Last alert", value: model.lastAlertText)
            }
            .font(.system(size: 12))

            Text(model.warmupText)
                .font(.footnote)
                .foregroundStyle(.secondary)

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
