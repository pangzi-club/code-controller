import AppKit
import Testing
@testable import DemoExplorer

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
}
