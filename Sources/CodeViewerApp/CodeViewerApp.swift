import AppKit
import CodeViewer
import SwiftUI

@main
struct CodeViewerApp: App {
    @StateObject private var settings = SettingsStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        // A Window scene is a single unique instance, so the default reopen
        // handling and openWindow(id:) can never produce a second main window.
        Window("", id: "main") {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 760, minHeight: 500)
                .onAppear {
                    appDelegate.openMainWindow = { openWindow(id: "main") }
                }
        }
        .defaultSize(width: 1080, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(l10nString("Toggle Sidebar")) {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }

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

/// A Dock click (or `open`) on a running app arrives as
/// `applicationShouldHandleReopen`. On macOS 14/15 the default handling already
/// re-shows the closed window, so returning `true` is enough on its own. The
/// delayed fallback covers older systems whose default handling opens nothing,
/// and a single-flight flag absorbs the second event of a Dock double click.
/// The main scene is a `Window`, so the fallback cannot create a duplicate
/// window even if it fires after the system restored one.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    private var reopenPending = false

    /// SwiftUI terminates an app whose only remaining scene is a closed
    /// `Window`, so keep it resident like a `WindowGroup` app: closing the last
    /// window must leave the Dock icon active for the reopen path above.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag, !reopenPending else { return true }
        reopenPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.reopenPending = false
            let restored = NSApplication.shared.windows.contains {
                $0.isVisible && $0.canBecomeMain
            }
            if !restored { self.openMainWindow?() }
        }
        return true
    }
}
