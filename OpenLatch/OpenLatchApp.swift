import SwiftUI
import AppIntents

@main
struct OpenLatchApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() { OpenLatchShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(.blue)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        if model.storageFailed { model.reload() }
                        if model.screen == .everyday || model.screen == .test { model.connect() }
                    } else if phase == .background { model.pause() }
                }
        }
    }
}
