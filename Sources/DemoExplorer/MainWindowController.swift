import AppKit
import Combine

/// What the detail pane currently shows: a sidebar folder or the settings page.
enum SidebarSelection: Hashable {
    case folder(UUID)
    case settings
}

/// Owns the main window: a unified toolbar carrying the sidebar toggle plus
/// contextual folder actions, a white sidebar pane and a detail pane swapped
/// on selection, window-title updates, and manual frame persistence.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let folders: FolderStore
    private let sidebar: SidebarViewController
    private let detail = DetailContainerViewController()
    private let toolbar = NSToolbar(identifier: "MainWindowToolbar")
    private var selection: SidebarSelection?
    private var foldersCancellable: AnyCancellable?

    init(settings: SettingsStore, folders: FolderStore) {
        self.settings = settings
        self.folders = folders

        let sidebar = SidebarViewController(folders: folders)
        self.sidebar = sidebar

        // System sidebar item: full-height pane with native collapse animation,
        // and the reason NSSplitViewController.toggleSidebar (toolbar button +
        // ⌥⌘S) works. The pane stays white because SidebarViewController draws
        // its own opaque background over the sidebar material.
        let item = NSSplitViewItem(sidebarWithViewController: sidebar)
        item.minimumThickness = 220
        item.maximumThickness = 360

        let split = NSSplitViewController()
        split.addSplitViewItem(item)
        split.addSplitViewItem(NSSplitViewItem(viewController: detail))
        split.splitView.setPosition(260, ofDividerAt: 0)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.displayName
        window.contentViewController = split
        window.contentMinSize = WindowFramePersistence.minSize
        window.backgroundColor = .controlBackgroundColor
        // The transparent titlebar keeps the toolbar white; the hairline under
        // it is drawn by the panes (BackgroundColorView.topHairline), so the
        // system separator is disabled and can never double up.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unified

        super.init(window: window)

        toolbar.delegate = self
        window.toolbar = toolbar

        // Manual frame persistence under a fixed key — see WindowFramePersistence.
        window.setFrameAutosaveName("")
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let defaultScreen = NSScreen.main?.visibleFrame ?? screens.first {
            window.setFrame(
                WindowFramePersistence.launchFrame(defaultScreen: defaultScreen, screens: screens),
                display: false
            )
        }
        window.delegate = self

        sidebar.onSelect = { [weak self] selection in self?.select(selection) }
        // A removed folder must leave the detail pane.
        foldersCancellable = folders.foldersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.validateSelection() }

        selection = folders.folders.first.map { .folder($0.id) }
        updateDetail()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Selection

    func select(_ selection: SidebarSelection?) {
        guard selection != self.selection else { return }
        self.selection = selection
        sidebar.reflectSelection(selection)
        updateDetail()
    }

    func selectSettings() {
        select(.settings)
    }

    func addFolderAndSelect() {
        guard let url = FolderPicker.chooseFolder(), let folder = folders.add(url) else { return }
        select(.folder(folder.id))
    }

    private func validateSelection() {
        guard case .folder(let id)? = selection,
              !folders.folders.contains(where: { $0.id == id }) else { return }
        select(nil)
    }

    private func updateDetail() {
        switch selection {
        case .settings:
            detail.show(SettingsViewController(settings: settings))
            window?.title = l10n("Settings")
        case .folder(let id):
            if let folder = folders.folders.first(where: { $0.id == id }) {
                detail.show(FileListViewController(folder: folder))
                window?.title = folder.name
            } else {
                showPlaceholder()
            }
        case nil:
            showPlaceholder()
        }
    }

    private func showPlaceholder() {
        detail.show(PlaceholderViewController(hasFolders: !folders.folders.isEmpty) { [weak self] in
            self?.addFolderAndSelect()
        })
        window?.title = AppInfo.displayName
    }

    // MARK: Toolbar

    // The toolbar is static: just the sidebar toggle (folder reveal/refresh
    // live in row context menus). The window title renders inline next to it.

    // MARK: Frame persistence (NSWindowDelegate)

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }
    func windowWillClose(_ notification: Notification) { saveFrame() }

    /// Saves under the fixed `mainWindowFrame` key, deliberately bypassing
    /// NSWindow's own autosave: it depends on the system restore pipeline,
    /// which never fires for the unbundled `swift run` binary. `swift run`
    /// and the .app therefore share one deterministic code path — each in its
    /// own UserDefaults domain, which is expected.
    private func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(
            NSStringFromRect(window.frame),
            forKey: WindowFramePersistence.frameKey
        )
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == .toggleSidebar else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        // Nil target: resolves down the responder chain to the split view
        // controller, which collapses the sidebar item natively.
        item.image = symbolImage("sidebar.leading", pointSize: 15)
        item.label = l10n("Toggle Sidebar")
        item.toolTip = l10n("Toggle Sidebar")
        item.action = #selector(NSSplitViewController.toggleSidebar(_:))
        return item
    }
}

/// Swaps the detail pane's child view controller, pinning its view edge to edge.
@MainActor
final class DetailContainerViewController: NSViewController {
    private var current: NSViewController?

    override func loadView() {
        view = BackgroundColorView(backgroundColor: .controlBackgroundColor, topHairline: true)
    }

    func show(_ viewController: NSViewController) {
        guard viewController !== current else { return }
        let old = current
        current = viewController

        if let old {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(viewController)
        view.addSubview(viewController.view)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

/// Empty-state page shown while no sidebar entry is selected.
@MainActor
final class PlaceholderViewController: NSViewController {
    private let hasFolders: Bool
    private let addFolder: () -> Void

    init(hasFolders: Bool, onAddFolder: @escaping () -> Void) {
        self.hasFolders = hasFolders
        self.addFolder = onAddFolder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let message = hasFolders ? "Select a folder on the left" : "Add a folder to get started"

        let icon = NSImageView()
        icon.image = symbolImage("folder", pointSize: 40, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        badge.layer?.cornerRadius = 40
        badge.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 80),
            badge.heightAnchor.constraint(equalToConstant: 80),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])

        let label = NSTextField(labelWithString: l10n(message))
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [badge, label])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX

        if !hasFolders {
            let button = NSButton(title: l10n("Add Folder"), target: self, action: #selector(addClicked))
            button.controlSize = .large
            button.bezelColor = .controlAccentColor
            stack.addView(button, in: .center)
        }

        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }

    @objc private func addClicked() {
        addFolder()
    }
}

/// Symbol image helper; point size and weight approximate the SwiftUI
/// `.font(.system(size:weight:))` styling the template used previously.
func symbolImage(_ name: String, pointSize: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) ?? NSImage()
}
