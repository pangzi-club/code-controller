import SwiftUI

@main
struct DemoExplorerApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 760, minHeight: 500)
                .background(WindowFrameAutosaver.mainWindow)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}
