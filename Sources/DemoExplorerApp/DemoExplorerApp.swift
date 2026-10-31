import DemoExplorer
import SwiftUI

@main
struct DemoExplorerApp: App {
    @StateObject private var settings = SettingsStore()

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1080, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowStyle(.hiddenTitleBar)

        // A standard Settings scene: singleton, fixed to its content size,
        // centered, and opened from the app menu (⌘,). It is not restored at
        // launch and needs no programmatic opener.
        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
