import SwiftUI

enum RadFlagSceneID {
    static let settings = "settings"
}

@main
struct RadFlagApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.statusSymbolName)
        }
        .menuBarExtraStyle(.window)

        Window("RadFlag Settings", id: RadFlagSceneID.settings) {
            SettingsView(model: model)
        }
    }
}
