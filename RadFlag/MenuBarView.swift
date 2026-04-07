import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Label("\(model.statusText)    \(model.loadWindowShortText) \(model.currentLoadText)", systemImage: model.statusSymbolName)

            Divider()

            metricRow("Recent load average:", model.recentAverageText)
            metricRow("Baseline load:", model.baselineText)
            metricRow("Recent/Baseline Ratio:", model.ratioText)
            metricRow("Top process name:", model.topProcessNameText)
            metricRow("Top process PID:", model.topProcessPIDText)
            metricRow("\(model.processWindowText) CPU avg:", model.topProcessCPUText)
            metricRow("Warning Trigger:", model.triggerReasonText)
            metricRow("Power source:", model.powerSourceText)
            metricRow("Last alert:", model.lastAlertText)
            
            /*
            Divider()

            ForEach(model.monitoringStatusRows, id: \.label) { row in
                metricRow(row.label, row.value)
            }
            */
            
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
