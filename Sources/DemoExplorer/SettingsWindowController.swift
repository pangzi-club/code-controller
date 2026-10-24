import AppKit

/// Standard ⌘, settings window: a small fixed-size titled window owning the
/// settings UI, separate from the main window (the native pattern — settings
/// is a window, not a page inside the main window).
@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore) {
        let content = SettingsViewController(settings: settings)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n("Settings")
        window.titlebarSeparatorStyle = .none
        window.isRestorable = false
        // The controller owns the window for the app's lifetime; closing must
        // not deallocate it out from under us.
        window.isReleasedWhenClosed = false
        window.contentViewController = content
        // fittingSize is unreliable before a layout pass (returns a compressed
        // size that clipped the segmented control out of the window).
        content.view.layoutSubtreeIfNeeded()
        let fitting = content.view.fittingSize
        // Sized for growth: the floor leaves room for future settings
        // sections beyond the current General card.
        window.setContentSize(NSSize(width: max(fitting.width, 480), height: max(fitting.height, 320)))

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the window, or re-fronts it if already visible.
    func showSettings() {
        showWindow(nil)
    }
}
