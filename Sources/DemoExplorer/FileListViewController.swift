import AppKit

/// Detail page listing a folder's direct children inside a card.
@MainActor
final class FileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let folder: Folder
    private var items: [FileItem] = []
    private var loadFailed = false

    private let tableView = ContextMenuTableView()
    private let scrollView = NSScrollView()
    private let card = NSBox()
    private let headlineLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var errorState: NSView!
    private var emptyState: NSView!
    private var cardTopToHeader: NSLayoutConstraint!
    private var cardTopToView: NSLayoutConstraint!

    init(folder: Folder) {
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView()

        makeCard()

        let cardHost = ShadowContainer(content: card)
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardHost)

        headlineLabel.stringValue = folder.name
        headlineLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        headlineLabel.textColor = .labelColor
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headlineLabel)

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)

        cardTopToHeader = cardHost.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10)
        cardTopToView = cardHost.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 16)
        cardTopToView.isActive = false
        NSLayoutConstraint.activate([
            headlineLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            headlineLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            countLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 6),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            cardTopToHeader,
            cardHost.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardHost.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardHost.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])

        reload()
    }

    // MARK: UI construction

    private func makeCard() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowHeight = 50
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        // The SwiftUI original highlighted rows on hover only; clicking did
        // not select, so the native selection highlight stays off.
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelection)
        tableView.rowMenuProvider = { [weak self] row in self?.menu(forItemAt: row) }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        // The scrollbar only occupies space (or renders, in the legacy style)
        // while the list actually overflows.
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        card.boxType = .custom
        card.borderWidth = 1
        card.borderColor = .separatorColor
        card.cornerRadius = 10
        card.fillColor = .controlBackgroundColor
        card.contentViewMargins = NSSize(width: 0, height: 0)
        card.contentView = scrollView

        errorState = statusState(icon: "exclamationmark.triangle", text: "Couldn't read this folder. It may have been moved or deleted.")
        emptyState = statusState(icon: "tray", text: "This folder is empty")

        guard let container = card.contentView else { return }
        for state in [errorState!, emptyState!] {
            state.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(state)
            NSLayoutConstraint.activate([
                state.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                state.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
    }

    private func statusState(icon: String, text: String) -> NSView {
        let imageView = NSImageView(image: symbolImage(icon, pointSize: 34, weight: .light))
        imageView.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: l10n(text))
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        return stack
    }

    // MARK: Loading

    private func reload() {
        if let loaded = FileLoader.load(from: folder.url) {
            items = loaded
            loadFailed = false
        } else {
            items = []
            loadFailed = true
        }
        tableView.reloadData()
        updateStates()
    }

    private func updateStates() {
        countLabel.stringValue = l10n("%lld items", items.count)
        countLabel.isHidden = loadFailed
        cardTopToHeader.isActive = !loadFailed
        cardTopToView.isActive = loadFailed
        scrollView.isHidden = loadFailed || items.isEmpty
        errorState.isHidden = !loadFailed
        emptyState.isHidden = loadFailed || !items.isEmpty
    }

    @objc private func openSelection() {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else { return }
        FileOpener.open(items[row].url)
    }

    private func menu(forItemAt row: Int) -> NSMenu? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]

        let menu = NSMenu()
        let open = NSMenuItem(title: l10n("Open"), action: #selector(openItemClicked), keyEquivalent: "")
        open.target = self
        open.representedObject = item.url
        menu.addItem(open)
        let reveal = NSMenuItem(title: l10n("Show in Finder"), action: #selector(revealItemClicked), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = item.url
        menu.addItem(reveal)
        return menu
    }

    @objc private func openItemClicked(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            FileOpener.open(url)
        }
    }

    @objc private func revealItemClicked(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            FileOpener.reveal(url)
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = FileRowView()
        view.showsBottomSeparator = row < items.count - 1
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]

        // Rebuilt per call; see SidebarViewController.viewFor.
        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let name = NSTextField(labelWithString: item.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.cell?.wraps = false
        name.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: self.subtitle(for: item))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.cell?.wraps = false
        subtitle.lineBreakMode = .byTruncatingTail

        let texts = NSStackView(views: [name, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        let cell = NSStackView(views: [icon, texts])
        cell.orientation = .horizontal
        cell.spacing = 12
        cell.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        cell.identifier = NSUserInterfaceItemIdentifier("FileRow")
        return cell
    }

    private func subtitle(for item: FileItem) -> String {
        if item.isDirectory { return l10n("Folder") }
        var parts: [String] = []
        if let size = item.byteSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let date = item.modificationDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }
}

/// File row with the template's subtle hover highlight and an indented hairline
/// separator between rows (58pt = 14pt inset + 32pt icon + 12pt spacing).
final class FileRowView: NSTableRowView {
    var showsBottomSeparator = true

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
        guard hovered, !isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        bounds.fill()
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        guard showsBottomSeparator else { return }
        NSColor.separatorColor.setFill()
        NSRect(x: 58, y: bounds.height - 1, width: bounds.width - 58, height: 1).fill()
    }
}
