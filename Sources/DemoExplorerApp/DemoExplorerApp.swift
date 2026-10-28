import AppKit
import DemoExplorer
import SwiftUI

@main
struct DemoExplorerApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                // minWidth/minHeight bound user resizing; WindowFrameAutosaver
                // restores the persisted frame (or the centered default)
                // before the window is first shown, so ideal* only applies on
                // the very first launch.
                .frame(minWidth: 760, idealWidth: 1080, minHeight: 500, idealHeight: 720)
                .background(WindowFrameAutosaver.mainWindow)
                .background(TitlebarFlattener())
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // Without a Settings scene there is no default Settings… menu
            // item; put it back with its standard shortcut. Commands can't
            // reach the openWindow environment action, so the item posts a
            // notification that ContentView forwards.
            CommandGroup(replacing: .appSettings) {
                Button(l10nString("Settings") + "…") {
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // The settings window: a single instance (re-opening focuses it),
        // fixed to its content size and centered. Deliberately a plain
        // Window scene rather than a Settings scene: opening a Settings
        // scene programmatically is macOS 14+ API, and its undocumented
        // showSettingsWindow: selector proved unreliable.
        Window(l10nString("Settings"), id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Extends the content under the titlebar and makes the titlebar transparent,
/// so the sidebar material reaches the traffic lights and the detail area shows
/// the page color instead of a solid toolbar strip across the whole window.
private struct TitlebarFlattener: NSViewRepresentable {
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
