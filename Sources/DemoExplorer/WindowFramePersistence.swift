import AppKit
import Foundation

/// Pure frame-persistence logic, testable without a live window.
enum WindowFramePersistence {
    /// UserDefaults key holding the saved frame in `NSStringFromRect` form.
    /// Deliberately not the `"NS Window Frame <name>"` key NSWindow's own
    /// autosave uses — this path never goes through that machinery.
    static let frameKey = "mainWindowFrame"

    /// First-launch window size; also applied when the saved frame is unusable.
    static let defaultSize = CGSize(width: 1080, height: 720)

    /// Kept in sync with the main window's `contentMinSize`.
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

    /// The frame to apply when the main window is created: the saved frame
    /// when still usable, otherwise the centered default.
    static func launchFrame(defaultScreen: NSRect, screens: [NSRect]) -> NSRect {
        let saved = savedFrame(from: UserDefaults.standard.string(forKey: frameKey))
        if let saved, isRestorable(saved, screens: screens) {
            return clamped(saved, to: screens)
        }
        return defaultFrame(in: defaultScreen)
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
