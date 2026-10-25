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
                // applies the persisted frame (or the centered default) one
                // tick after the window appears, so ideal* only sizes it for
                // that first tick.
                .frame(minWidth: 760, idealWidth: 1080, minHeight: 500, idealHeight: 720)
                .toolbarBackground(Color(nsColor: .controlBackgroundColor), for: .windowToolbar)
                .background(WindowFrameAutosaver.mainWindow)
                .background(TitlebarFlattener())
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        // The standard ⌘, preferences window: singleton, non-resizable,
        // centered and sized to its content; the App menu gains a Settings…
        // item with ⌘, when running as a real .app. The sidebar gear opens
        // it via SettingsWindowOpener (which also covers bare `swift run`).
        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}

/// Matches the window background to the content, so the frame edges and
/// overscroll areas stay white instead of the default gray. The hairline
/// under the toolbar is drawn by ContentView's top overlay; the system
/// separator is explicitly disabled so it can never double up with ours.
private struct TitlebarFlattener: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .controlBackgroundColor
            window.titlebarSeparatorStyle = .none
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
