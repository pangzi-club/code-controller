import AppKit
import Combine

/// Sidebar pane: the folder table with hover/selection styling, drag-and-drop
/// intake, the Add / Settings footer buttons, and per-row context menus.
@MainActor
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((UUID?) -> Void)?

    private let folders: FolderStore
    private var foldersCancellable: AnyCancellable?
    /// Mirrors the selected folder so table reloads (after add/remove) can
    /// restore the row without re-triggering the selection callback.
    private var selectedFolderID: UUID?
    private var isSyncingSelection = false

    private let tableView = ContextMenuTableView()
    private let countBadge = CountBadge()
    private var emptyState: NSView!

    init(folders: FolderStore) {
        self.folders = folders
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        // Explicit background: the pane must stay white even though the split
        // view's own background shows through transparent subviews. The
        // topHairline continues the toolbar separator across the sidebar.
        view = BackgroundColorView(backgroundColor: .controlBackgroundColor, topHairline: true)

        let header = makeHeader()
        let scroll = makeTable()
        let footer = makeFooter()
        emptyState = makeEmptyState()

        for subview in [header, scroll, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        scroll.addSubview(emptyState)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // The sidebar item extends full height under the toolbar; content
            // starts below its safe-area inset.
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        foldersCancellable = folders.foldersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.foldersDidChange() }
        foldersDidChange()
    }

    // MARK: Callbacks from MainWindowController

    /// Updates the highlighted row without notifying `onSelect` back.
    func reflectSelection(_ folderID: UUID?) {
        selectedFolderID = folderID
        syncRowSelection()
    }

    // MARK: UI construction

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: l10n("Folders"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let stack = NSStackView()
        stack.addView(title, in: .leading)
        stack.addView(countBadge, in: .trailing)
        return stack
    }

    private func makeTable() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FolderColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = 40
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowMenuProvider = { [weak self] row in self?.menu(forFolderAt: row) }
        // Folder intake by drag-and-drop; validated in the data source below.
        tableView.registerForDraggedTypes([.fileURL])

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        // No reserved scrollbar gutter (or legacy scrollbar) while the folder
        // list fits without scrolling.
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    private func makeEmptyState() -> NSView {
        let icon = NSImageView(image: symbolImage("folder.badge.plus", pointSize: 30, weight: .light))
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: l10n("Click the button below to add a folder"))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        return stack
    }

    private func makeFooter() -> NSView {
        let addButton = DashedButton(
            symbol: "plus",
            title: l10n("Add Folder"),
            target: self,
            action: #selector(addClicked)
        )
        addButton.setContentHuggingPriority(.init(1), for: .horizontal)
        addButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return addButton
    }

    // MARK: Store changes

    private func foldersDidChange() {
        countBadge.setCount(folders.folders.count)
        emptyState.isHidden = !folders.folders.isEmpty
        tableView.reloadData()
        syncRowSelection()
    }

    private func syncRowSelection() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        let previousRow = tableView.selectedRow
        if let id = selectedFolderID,
           let row = folders.folders.firstIndex(where: { $0.id == id }),
           row < tableView.numberOfRows {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            // Also covers the moment right after an add, when the table still
            // shows the pre-add row count (the store's publisher delivery is
            // deferred a tick); foldersDidChange reloads and calls back here.
            tableView.deselectAll(nil)
        }
        // Cells bake their selected-state styling in (white label text while
        // selected), so rows whose selection state changed must rebuild their
        // cells — otherwise a deselected row keeps its white-on-white text.
        let newRow = tableView.selectedRow
        var changed = IndexSet()
        if previousRow >= 0 { changed.insert(previousRow) }
        if newRow >= 0 { changed.insert(newRow) }
        guard !changed.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tableView.numberOfRows > 0 else { return }
            self.tableView.reloadData(
                forRowIndexes: changed,
                columnIndexes: IndexSet(integersIn: 0..<self.tableView.numberOfColumns)
            )
        }
    }

    // MARK: Actions

    @objc private func addClicked() {
        guard let url = FolderPicker.chooseFolder(), let folder = folders.add(url) else { return }
        onSelect?(folder.id)
    }

    @objc private func revealClicked(_ sender: NSMenuItem) {
        if let folder = folder(for: sender) {
            FileOpener.reveal(folder.url)
        }
    }

    @objc private func removeClicked(_ sender: NSMenuItem) {
        if let folder = folder(for: sender) {
            folders.remove(folder)
        }
    }

    private func folder(for sender: NSMenuItem) -> Folder? {
        guard let id = sender.representedObject as? UUID else { return nil }
        return folders.folders.first { $0.id == id }
    }

    private func menu(forFolderAt row: Int) -> NSMenu? {
        guard folders.folders.indices.contains(row) else { return nil }
        let folder = folders.folders[row]

        let menu = NSMenu()
        let reveal = NSMenuItem(
            title: l10n("Show in Finder"),
            action: #selector(revealClicked),
            keyEquivalent: ""
        )
        reveal.target = self
        reveal.representedObject = folder.id
        menu.addItem(reveal)
        menu.addItem(.separator())
        let remove = NSMenuItem(
            title: l10n("Remove"),
            action: #selector(removeClicked),
            keyEquivalent: ""
        )
        remove.target = self
        remove.representedObject = folder.id
        menu.addItem(remove)
        return menu
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        folders.folders.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let row = tableView.selectedRow
        if folders.folders.indices.contains(row) {
            let folder = folders.folders[row]
            selectedFolderID = folder.id
            onSelect?(folder.id)
        } else {
            selectedFolderID = nil
            onSelect?(nil)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard folders.folders.indices.contains(index) else { return nil }
        let folder = folders.folders[index]
        let isSelected = tableView.isRowSelected(index)

        // Rebuilt per call: fine for a sidebar-sized list, and it keeps the
        // template free of nib registrations and reuse pools.
        let tile = FolderTileView(color: FolderPalette.color(for: folder.url.path))
        tile.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 28),
            tile.heightAnchor.constraint(equalToConstant: 28),
        ])
        let icon = NSImageView(image: symbolImage("folder.fill", pointSize: 12, weight: .semibold))
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])

        // No text colors baked in: NSTextField adapts label/secondary colors
        // to the row's selection and emphasis state on its own (and must, or
        // deselection leaves stale white text — see syncRowSelection).
        let name = singleLineLabel(
            folder.name,
            font: .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        )
        let path = singleLineLabel(folder.url.abbreviatedPath, font: .systemFont(ofSize: 10), middleTruncating: true)
        path.textColor = .secondaryLabelColor

        let texts = NSStackView(views: [name, path])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1

        let cell = NSStackView(views: [tile, texts])
        cell.orientation = .horizontal
        cell.spacing = 10
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        cell.identifier = NSUserInterfaceItemIdentifier("FolderRow")
        return cell
    }

    private func singleLineLabel(_ string: String, font: NSFont, middleTruncating: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = font
        label.cell?.wraps = false
        label.lineBreakMode = middleTruncating ? .byTruncatingMiddle : .byTruncatingTail
        return label
    }

    // MARK: Drag-and-drop intake

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let url = firstDraggedURL(info), isDirectory(url) else { return [] }
        // Highlight the whole table rather than a specific row.
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let url = firstDraggedURL(info), isDirectory(url) else { return false }
        guard let folder = folders.add(url) else { return false }
        onSelect?(folder.id)
        return true
    }

    private func firstDraggedURL(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }
}

// MARK: - Row / cell styling

/// Row with the template's hover highlight and rounded accent selection.
final class SidebarRowView: NSTableRowView {
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected {
            // Native emphasis: accent fill while the window is key, flat gray
            // otherwise (cell text follows via its background style).
            (isEmphasized ? NSColor.controlAccentColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        } else if hovered {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }
}

/// Rounded color tile behind the folder icon; draw-based so the color stays
/// appearance-dynamic.
final class FolderTileView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

// MARK: - Folder colors

enum FolderPalette {
    static let colors: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange,
        .systemGreen, .systemTeal, .systemCyan, .systemIndigo, .systemBrown,
    ]

    /// djb2 hash: `hashValue` changes on every launch, this keeps each folder's
    /// color stable across launches.
    static func colorIndex(for path: String) -> Int {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return Int(hash % UInt64(colors.count))
    }

    static func color(for path: String) -> NSColor {
        colors[colorIndex(for: path)]
    }
}

extension URL {
    /// Replaces the home directory prefix with "~" for display.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
