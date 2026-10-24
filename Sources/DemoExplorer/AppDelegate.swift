import AppKit
import Combine

/// Application delegate: owns the shared stores, applies the theme app-wide,
/// builds the menu bar in code (a SwiftPM-only package ships no MainMenu.xib)
/// and shows the main window on launch.
///
/// Public only because the thin `DemoExplorerApp` executable instantiates it.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let folders = FolderStore()
    private var mainWindowController: MainWindowController?
    private var themeCancellable: AnyCancellable?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        themeCancellable = settings.$theme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.applyAppearance(theme) }
        applyAppearance(settings.theme)
        buildMainMenu()

        let controller = MainWindowController(settings: settings, folders: folders)
        mainWindowController = controller
        controller.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Single-window utility: closing the window quits the app.
        true
    }

    // MARK: Theme

    private func applyAppearance(_ theme: ThemePreference) {
        // nil follows the system-wide appearance; windows inherit from NSApp.
        NSApp.appearance = theme.appearance
    }

    // MARK: Menu bar

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = appMenu()
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu()
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu()
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu()
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        // Lets the system manage per-window entries in the Window menu.
        NSApp.windowsMenu = windowItem.submenu
    }

    private func appMenu() -> NSMenu {
        let name = AppInfo.displayName
        let menu = NSMenu(title: name)
        menu.addItem(.item(l10n("About %@"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Settings") + "…", #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Hide %@"), #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Quit %@"), #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: l10n("File"))
        menu.addItem(.item(l10n("Add Folder") + "…", #selector(addFolder), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Close"), #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }

    private func editMenu() -> NSMenu {
        // Standard selectors with no target: they reach the first responder,
        // which makes keyboard editing work in every text field.
        let menu = NSMenu(title: l10n("Edit"))
        menu.addItem(.item(l10n("Cut"), #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(.item(l10n("Copy"), #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(.item(l10n("Paste"), #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(.item(l10n("Select All"), #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        // Nil target: the action reaches the window's NSSplitViewController,
        // which toggles the sidebar-behavior split item.
        let menu = NSMenu(title: l10n("View"))
        menu.addItem(.item(
            l10n("Toggle Sidebar"),
            #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .option]
        ))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: l10n("Window"))
        menu.addItem(.item(l10n("Minimize"), #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(.item(l10n("Zoom"), #selector(NSWindow.performZoom(_:))))
        return menu
    }

    // MARK: Actions

    @objc private func showSettings() {
        mainWindowController?.selectSettings()
    }

    @objc private func addFolder() {
        mainWindowController?.addFolderAndSelect()
    }
}

private extension NSMenuItem {
    /// Convenience constructor; a nil target (the default) resolves the action
    /// through the responder chain at click time.
    static func item(
        _ title: String,
        _ action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
