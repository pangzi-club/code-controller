import AppKit
import SwiftUI

/// Gives the hosting window a stable AppKit frame-autosave name so its
/// position and size persist across launches under a constant UserDefaults
/// key (`"NS Window Frame <name>"`).
///
/// SwiftUI already autosaves WindowGroup frames, but under a name derived
/// from the view hierarchy — any change to the content view's modifiers
/// silently invalidates the saved frame. Clearing that name and setting our
/// own keeps the persisted frame stable across code changes.
struct WindowFrameAutosaver: NSViewRepresentable {
    /// The instance to attach to the main window's content.
    static let mainWindow = WindowFrameAutosaver(name: "MainWindow")

    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view is attached to its window one run-loop tick after creation;
        // by then SwiftUI has already assigned its derived autosave name.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setFrameAutosaveName("")
            window.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
