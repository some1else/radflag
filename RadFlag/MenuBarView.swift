import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Label("\(model.statusText)    5m \(model.currentLoadText)", systemImage: model.statusSymbolName)

            Divider()

            metricRow("Recent average", model.recentAverageText)
            metricRow("Baseline", model.baselineText)
            metricRow("Ratio", model.ratioText)
            metricRow("Top process", model.topProcessNameText)
            metricRow("PID", model.topProcessPIDText)
            metricRow("5m CPU avg", model.topProcessCPUText)
            metricRow("Trigger", model.triggerReasonText)
            metricRow("Power", model.powerSourceText)
            metricRow("Last alert", model.lastAlertText)

            Divider()

            Text(model.warmupText)

            Divider()

            Button(model.muteButtonTitle) {
                model.toggleMute()
            }
            .disabled(!model.canToggleMute)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: RadFlagSceneID.settings)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Button("Sample now") {
                model.sampleNow()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        Text("\(label)  \(value)")
    }
}
