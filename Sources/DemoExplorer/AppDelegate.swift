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
    private var settingsWindowController: SettingsWindowController?
    private var themeCancellable: AnyCancellable?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        themeCancellable = settings.$theme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.applyAppearance(theme) }
        applyAppearance(settings.theme)

        let controller = MainWindowController(settings: settings, folders: folders)
        mainWindowController = controller
        // Built after the controller exists: File → Open targets it
        // explicitly (a nil target's validation stalls at the first responder,
        // which does not implement the action).
        buildMainMenu(mainWindow: controller)
        controller.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Single-window utility: closing the window quits the app. The
        // settings window is excluded (it is not released on close).
        sender.windows.count == 1
    }

    // MARK: Theme

    private func applyAppearance(_ theme: ThemePreference) {
        // nil follows the system-wide appearance. Setting NSApp.appearance
        // alone does not propagate to already-created windows at runtime —
        // their chrome and custom-drawn views keep the previous appearance
        // until relaunch — so mirror it onto every window explicitly.
        NSApp.appearance = theme.appearance
        for window in NSApp.windows {
            window.appearance = theme.appearance
        }
    }

    // MARK: Menu bar

    private func buildMainMenu(mainWindow: MainWindowController) {
        let mainMenu = NSMenu()

        for menu in [appMenu(), fileMenu(mainWindow: mainWindow), editMenu(), viewMenu(), windowMenu()] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }

        NSApp.mainMenu = mainMenu
        // Let the system manage these standard submenus' contents.
        NSApp.windowsMenu = mainMenu.item(withTitle: l10n("Window"))?.submenu
        NSApp.servicesMenu = mainMenu.item(withTitle: l10n("Services"))?.submenu
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: AppInfo.displayName)
        menu.addItem(.item(l10n("About"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Settings") + "…", #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Hide"), #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        menu.addItem(.item(
            l10n("Hide Others"),
            #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(.item(l10n("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Quit"), #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func fileMenu(mainWindow: MainWindowController) -> NSMenu {
        let menu = NSMenu(title: l10n("File"))
        // No ⌘N: system-wide that means "new window/document", not "add".
        menu.addItem(.item(l10n("Add Folder") + "…", #selector(addFolder)))
        menu.addItem(.separator())
        // Explicit target: validation goes straight to the controller (which
        // gates on the file list's selection) instead of stalling at the
        // first responder.
        menu.addItem(.item(
            l10n("Open"),
            #selector(MainWindowController.openSelectedFile(_:)),
            keyEquivalent: "o",
            target: mainWindow
        ))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Close"), #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }

    private func editMenu() -> NSMenu {
        // Standard selectors with no target: they reach the first responder,
        // which makes keyboard editing work in every text field.
        let menu = NSMenu(title: l10n("Edit"))
        menu.addItem(.item(l10n("Undo"), NSSelectorFromString("undo:"), keyEquivalent: "z"))
        menu.addItem(.item(l10n("Redo"), NSSelectorFromString("redo:"), keyEquivalent: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Cut"), #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(.item(l10n("Copy"), #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(.item(l10n("Paste"), #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(.item(l10n("Select All"), #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())
        let services = NSMenuItem(title: l10n("Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: l10n("Services"))  // populated via NSApp.servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(.item(
            l10n("Emoji & Symbols"),
            #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " ",
            modifiers: [.command, .control]
        ))
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
        menu.addItem(.separator())
        menu.addItem(.item(l10n("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: Actions

    @objc private func showSettings() {
        // Standard ⌘, behavior: open once, then re-front the same window.
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }
        settingsWindowController?.showSettings()
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
