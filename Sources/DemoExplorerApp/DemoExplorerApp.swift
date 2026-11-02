import AppKit
import DemoExplorer
import SwiftUI

@main
struct DemoExplorerApp: App {
    @StateObject private var settings = SettingsStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 760, minHeight: 500)
                .onAppear {
                    appDelegate.openMainWindow = { openWindow(id: "main") }
                    appDelegate.mainWindowAppeared()
                }
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

/// A Dock click (or `open`) on a running app arrives as
/// `applicationShouldHandleReopen`, but SwiftUI does not recreate the window of
/// a closed `WindowGroup`, so the app would activate with no UI. The only API
/// that opens a `WindowGroup` window is the environment's open action, and it
/// is reachable only from a view — the root view hands it up when it appears.
///
/// A double click on the Dock delivers two reopen events before the first
/// window exists, so the request is single-flight: it stays pending until the
/// window reports in, and a second event in that window of time is ignored.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    private var reopenPending = false

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, !reopenPending {
            reopenPending = true
            openMainWindow?()
            // Safety net for an open action that never produces a window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.reopenPending = false
            }
        }
        return true
    }

    /// The root view calls this once its window exists, ending the single
    /// flight so later Dock clicks can open a window again.
    func mainWindowAppeared() {
        reopenPending = false
    }
}
