import AppKit
import Testing
@testable import DemoExplorer

// Serialized: the launchFrame tests read and write the shared
// `mainWindowFrame` UserDefaults key, which parallel runs would clobber.
@Suite(.serialized)
struct WindowFrameTests {
    let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let sideScreen = NSRect(x: 1920, y: 0, width: 1280, height: 800)
    var screens: [NSRect] { [screen, sideScreen] }

    @Test("savedFrame parses NSStringFromRect round-trips and rejects garbage")
    func parseSavedFrame() {
        let frame = NSRect(x: 10, y: 20, width: 1080, height: 720)
        #expect(WindowFramePersistence.savedFrame(from: NSStringFromRect(frame)) == frame)

        #expect(WindowFramePersistence.savedFrame(from: nil) == nil)
        #expect(WindowFramePersistence.savedFrame(from: "not a rect") == nil)
    }

    @Test("restorable requires minimum size and some screen overlap")
    func restorable() {
        #expect(WindowFramePersistence.isRestorable(
            NSRect(x: 0, y: 0, width: 1080, height: 720), screens: screens
        ))
        // Exactly at the minimum is still fine.
        #expect(WindowFramePersistence.isRestorable(
            NSRect(x: 0, y: 0, width: 760, height: 500), screens: screens
        ))
        // Too small in either dimension.
        #expect(!WindowFramePersistence.isRestorable(
            NSRect(x: 0, y: 0, width: 700, height: 720), screens: screens
        ))
        #expect(!WindowFramePersistence.isRestorable(
            NSRect(x: 0, y: 0, width: 1080, height: 400), screens: screens
        ))
        // Fully off-screen, e.g. saved on a display that is now unplugged.
        #expect(!WindowFramePersistence.isRestorable(
            NSRect(x: -5000, y: -5000, width: 1080, height: 720), screens: screens
        ))
        // Partially on-screen is fine.
        #expect(WindowFramePersistence.isRestorable(
            NSRect(x: -500, y: 0, width: 1080, height: 720), screens: screens
        ))
    }

    @Test("clamping pulls an overhanging frame onto its screen, keeping size")
    func clampOverhang() {
        let clamped = WindowFramePersistence.clamped(
            NSRect(x: -300, y: 200, width: 1080, height: 720), to: screens
        )
        #expect(clamped.origin.x == 0)
        #expect(clamped.origin.y == 200)
        #expect(clamped.width == 1080)
        #expect(clamped.height == 720)
    }

    @Test("clamping caps a frame larger than the screen")
    func clampOversized() {
        let clamped = WindowFramePersistence.clamped(
            NSRect(x: 100, y: 100, width: 3000, height: 2000), to: [screen]
        )
        #expect(clamped.width == screen.width)
        #expect(clamped.height == screen.height)
        #expect(clamped.origin == screen.origin)
    }

    @Test("clamping picks the screen with the larger overlap")
    func clampPicksOverlappingScreen() {
        // maxX 2780: overlaps screen by 220pt and sideScreen by 860pt.
        let clamped = WindowFramePersistence.clamped(
            NSRect(x: 1700, y: 0, width: 1080, height: 720), to: screens
        )
        #expect(clamped.minX == sideScreen.minX)
        #expect(clamped.maxX <= sideScreen.maxX)
    }

    @Test("clamping an off-screen frame lands it on the nearest screen")
    func clampOffScreen() {
        // Beyond both screens; sideScreen's center is the nearest.
        let clamped = WindowFramePersistence.clamped(
            NSRect(x: 5000, y: 0, width: 1080, height: 720), to: screens
        )
        #expect(clamped.maxX == sideScreen.maxX)
        #expect(clamped.maxY <= sideScreen.maxY)
    }

    @Test("default frame is the default size centered in the screen")
    func defaultFrame() {
        let frame = WindowFramePersistence.defaultFrame(in: screen)
        #expect(frame.width == WindowFramePersistence.defaultSize.width)
        #expect(frame.height == WindowFramePersistence.defaultSize.height)
        #expect(frame.midX == screen.midX)
        #expect(frame.midY == screen.midY)
    }

    @Test("default frame is capped to a screen smaller than the default size")
    func defaultFrameTinyScreen() {
        let tiny = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = WindowFramePersistence.defaultFrame(in: tiny)
        #expect(frame.width == tiny.width)
        #expect(frame.height == tiny.height)
        #expect(frame.midX == tiny.midX)
        #expect(frame.midY == tiny.midY)
    }

    @Test("launchFrame returns the clamped saved frame when usable")
    func launchFrameUsesSaved() {
        let saved = NSRect(x: -300, y: 100, width: 1080, height: 720)
        UserDefaults.standard.set(NSStringFromRect(saved), forKey: WindowFramePersistence.frameKey)
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.frameKey) }

        let frame = WindowFramePersistence.launchFrame(defaultScreen: screen, screens: screens)

        #expect(frame == WindowFramePersistence.clamped(saved, to: screens))
    }

    @Test("launchFrame falls back to the centered default when nothing usable is stored")
    func launchFrameFallsBack() {
        func fallbackFrame() -> NSRect {
            WindowFramePersistence.launchFrame(defaultScreen: screen, screens: screens)
        }

        UserDefaults.standard.removeObject(forKey: WindowFramePersistence.frameKey)
        #expect(fallbackFrame() == WindowFramePersistence.defaultFrame(in: screen))

        // Saved on a display that no longer exists.
        UserDefaults.standard.set(
            NSStringFromRect(NSRect(x: -5000, y: -5000, width: 1080, height: 720)),
            forKey: WindowFramePersistence.frameKey
        )
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.frameKey) }
        #expect(fallbackFrame() == WindowFramePersistence.defaultFrame(in: screen))
    }
}
