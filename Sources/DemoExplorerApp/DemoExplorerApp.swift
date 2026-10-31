import AppKit
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
                .background(TitlebarFlattener())
        }
        .defaultSize(width: 1080, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: true))

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

/// Extends the content under the titlebar and makes the titlebar transparent,
/// so the sidebar material reaches the traffic lights and the detail area shows
/// the page color instead of a solid toolbar strip across the whole window.
struct TitlebarFlattener: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .controlBackgroundColor
            window.titlebarSeparatorStyle = .none
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
