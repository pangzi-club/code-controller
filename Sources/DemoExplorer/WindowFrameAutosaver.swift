import AppKit
import SwiftUI

/// Pure frame-persistence logic, testable without a live window.
enum WindowFramePersistence {
    /// UserDefaults key holding the saved frame in `NSStringFromRect` form.
    /// Deliberately not the `"NS Window Frame <name>"` key NSWindow's own
    /// autosave uses — this path never goes through that machinery.
    static let frameKey = "mainWindowFrame"

    /// First-launch window size; also applied when the saved frame is unusable.
    static let defaultSize = CGSize(width: 1080, height: 720)

    /// Kept in sync with the content view's `.frame(minWidth:minHeight:)`.
    static let minSize = CGSize(width: 760, height: 500)

    /// Parses a saved `NSStringFromRect` value; nil when missing or garbage.
    static func savedFrame(from value: String?) -> NSRect? {
        guard let value else { return nil }
        let rect = NSRectFromString(value)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// A saved frame is restorable when it respects the minimum size and at
    /// least partially lands on a visible screen (i.e. that screen still
    /// exists — handles unplugged displays).
    static func isRestorable(_ frame: NSRect, screens: [NSRect]) -> Bool {
        frame.width >= minSize.width
            && frame.height >= minSize.height
            && screens.contains { $0.intersects(frame) }
    }

    /// Pulls the frame fully onto the screen it overlaps most (ties, or no
    /// overlap at all, fall back to the nearest screen), capping its size to
    /// that screen first so a frame saved on a large display still fits.
    static func clamped(_ frame: NSRect, to screens: [NSRect]) -> NSRect {
        guard let screen = bestScreen(for: frame, in: screens) else { return frame }
        let width = min(frame.width, screen.width)
        let height = min(frame.height, screen.height)
        let x = min(max(frame.minX, screen.minX), screen.maxX - width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The default size centered in the given screen, capped to it.
    static func defaultFrame(in screen: NSRect) -> NSRect {
        let width = min(defaultSize.width, screen.width)
        let height = min(defaultSize.height, screen.height)
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func bestScreen(for frame: NSRect, in screens: [NSRect]) -> NSRect? {
        screens.min { lhs, rhs in
            let leftArea = overlapArea(lhs, frame)
            let rightArea = overlapArea(rhs, frame)
            if leftArea != rightArea { return leftArea > rightArea }
            return centerDistanceSquared(lhs, frame) < centerDistanceSquared(rhs, frame)
        }
    }

    private static func overlapArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        guard a.intersects(b) else { return 0 }
        let width = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let height = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return width * height
    }

    private static func centerDistanceSquared(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return dx * dx + dy * dy
    }
}

/// Persists the hosting window's frame manually, bypassing NSWindow's autosave
/// mechanism: it depends on the system restore pipeline, which never fires for
/// the unbundled `swift run` binary, and SwiftUI may override the name anyway.
///
/// On attach, the saved frame (or a centered 1080×720 default) is applied
/// before the window is first shown; user-driven moves, resizes and closes
/// write the frame back to UserDefaults. `swift run` and the .app therefore
/// share one deterministic code path — each in its own UserDefaults domain,
/// which is expected.
public struct WindowFrameAutosaver: NSViewRepresentable {
    /// The instance to attach to the main window's content.
    public static let mainWindow = WindowFrameAutosaver()

    public init() {}

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        let view = FrameRestoringView()
        view.onWindow = { window in
            Self.restoreBeforeFirstFrame(window, coordinator: context.coordinator)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    /// SwiftUI shows the window at its own default size before the next
    /// run-loop turn, so a plain async restore makes the window visibly jump.
    /// Instead, the window is hidden the moment the view attaches, the saved
    /// frame is applied, and only then is it made visible again.
    static func restoreBeforeFirstFrame(_ window: NSWindow, coordinator: Coordinator) {
        let alpha = window.alphaValue
        window.alphaValue = 0
        DispatchQueue.main.async {
            Self.restore(window)
            coordinator.observe(window)
            window.alphaValue = alpha
        }
    }

    /// Applies the saved frame, or the centered default when none is usable.
    static func restore(_ window: NSWindow) {
        // Stop NSWindow's own autosave from fighting ours.
        window.setFrameAutosaveName("")
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let defaultScreen = NSScreen.main?.visibleFrame ?? screens.first else { return }

        let saved = WindowFramePersistence.savedFrame(
            from: UserDefaults.standard.string(forKey: WindowFramePersistence.frameKey)
        )
        if let saved, WindowFramePersistence.isRestorable(saved, screens: screens) {
            window.setFrame(WindowFramePersistence.clamped(saved, to: screens), display: true)
        } else {
            window.setFrame(WindowFramePersistence.defaultFrame(in: defaultScreen), display: true)
        }
    }

    public final class Coordinator {
        private var observers: [NSObjectProtocol] = []

        /// Saves the frame whenever the user finishes moving or resizing the
        /// window, plus one last write on close.
        func observe(_ window: NSWindow) {
            observers.forEach(NotificationCenter.default.removeObserver)
            let names = [
                NSWindow.didMoveNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.willCloseNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { note in
                    guard let window = note.object as? NSWindow else { return }
                    UserDefaults.standard.set(
                        NSStringFromRect(window.frame),
                        forKey: WindowFramePersistence.frameKey
                    )
                }
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// Reports its window synchronously while SwiftUI is installing the content,
/// i.e. before the window is ordered front — early enough to hide it for the
/// frame restore without ever showing SwiftUI's default size.
private final class FrameRestoringView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private weak var lastWindow: NSWindow?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow, newWindow !== lastWindow else { return }
        lastWindow = newWindow
        onWindow?(newWindow)
    }
}
