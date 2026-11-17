import SwiftUI

/// Horizontal tab strip for the open documents of one workspace. Tabs flow
/// into a second row when one row cannot fit them; beyond two rows the tabs
/// stop shrinking and the strip scrolls horizontally instead.
struct DocumentTabBar: View {
    let tabs: [DocumentTab]
    let selectedTabID: DocumentTab.ID?
    let git: GitStatusStore
    let onSelect: (DocumentTab) -> Void
    let onClose: (DocumentTab) -> Void
    let onCloseOthers: (DocumentTab) -> Void
    let onCloseToLeft: (DocumentTab) -> Void
    let onCloseToRight: (DocumentTab) -> Void

    @State private var hoveredTabID: DocumentTab.ID?
    @State private var viewportWidth: CGFloat = 0
    @State private var rowCount = 1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                TabRowsLayout(containerWidth: availableRowWidth, onRowCountChange: updateRowCount) {
                    ForEach(tabs) { tab in
                        tabView(tab)
                            .id(tab.id)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .background(TabVerticalScrollLock())
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TabViewportWidthKey.self,
                        value: geometry.size.width
                    )
                }
            )
            .onChange(of: selectedTabID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: Self.height(forRows: rowCount))
        .onPreferenceChange(TabViewportWidthKey.self) { width in
            viewportWidth = width
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4

    private static func height(forRows rows: Int) -> CGFloat {
        CGFloat(rows) * TabRowsLayout.tabHeight
            + CGFloat(max(0, rows - 1)) * TabRowsLayout.defaultRowSpacing
            + verticalPadding * 2
    }

    private var availableRowWidth: CGFloat {
        guard viewportWidth > 0 else { return .infinity }
        return max(1, viewportWidth - Self.horizontalPadding * 2)
    }

    private func updateRowCount(_ rows: Int) {
        guard rows != rowCount else { return }
        DispatchQueue.main.async {
            guard rows != rowCount else { return }
            rowCount = rows
        }
    }

    /// Diff tabs are a second content kind: they carry a git-flavored icon
    /// instead of the file-type symbol, and no status badge (there is no file
    /// whose status could be shown).
    private func tabIcon(_ tab: DocumentTab) -> String {
        switch tab.content {
        case .file(let url, _): return FileIcon.symbolName(for: url, isDirectory: false)
        case .commitDiff: return "arrow.left.arrow.right"
        }
    }

    private func tabView(_ tab: DocumentTab) -> some View {
        let isSelected = tab.id == selectedTabID
        let isHovered = hoveredTabID == tab.id
        let showsCloseButton = isSelected || isHovered
        let gitStatus = tab.url.flatMap { git.status(for: $0) }

        return HStack(spacing: 4) {
            Button {
                onSelect(tab)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tabIcon(tab))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(tab.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 80, maxWidth: 200, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if let gitStatus {
                Text(gitStatus.badge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gitStatus.color)
                    .accessibilityLabel(l10n(gitStatus.labelKey))
                    .help(l10nString(gitStatus.labelKey))
            }

            if showsCloseButton {
                Button {
                    onClose(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(l10nString("Close Tab"))
                .accessibilityLabel(Text(l10nString("Close Tab")))
            } else {
                Color.clear
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: TabRowsLayout.tabHeight)
        .background {
            // Only the selected tab gets an outline; unselected tabs keep a
            // transparent one so the strip stays calm. strokeBorder draws
            // inside the shape, so the tab's height and spacing are untouched.
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            ZStack(alignment: .top) {
                shape.fill(
                    isSelected ? Color.primary.opacity(0.09)
                        : isHovered ? Color.primary.opacity(0.045)
                        : Color.clear
                )
                shape.strokeBorder(
                    isSelected ? Color.primary.opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .clipShape(shape)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
        .contextMenu {
            Button {
                onClose(tab)
            } label: {
                l10n("Close Tab")
            }
            Button {
                onCloseOthers(tab)
            } label: {
                l10n("Close Other Tabs")
            }
            Button {
                onCloseToLeft(tab)
            } label: {
                l10n("Close Tabs to the Left")
            }
            Button {
                onCloseToRight(tab)
            } label: {
                l10n("Close Tabs to the Right")
            }
            Divider()
            if let url = tab.url {
                Button {
                    FileOpener.reveal(url)
                } label: {
                    l10n("Show in Finder")
                }
            }
        }
        .help(helpText(for: tab))
    }

    private func helpText(for tab: DocumentTab) -> String {
        switch tab.content {
        case .file(let url, _): return url.abbreviatedPath
        case .commitDiff(let document): return document.commit.hash
        }
    }
}

private struct TabViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Flow layout capped at two rows. Tabs keep their ideal width while the
/// strip has room; once more than two rows would be needed, all tabs share
/// the width that fits two rows (down to their 80pt minimum), and the strip
/// scrolls horizontally for whatever still does not fit.
private struct TabRowsLayout: Layout {
    let containerWidth: CGFloat
    let onRowCountChange: (Int) -> Void
    var spacing: CGFloat = 2
    var rowSpacing = Self.defaultRowSpacing

    static let tabHeight: CGFloat = 38
    static let defaultRowSpacing: CGFloat = 4

    struct Plan {
        var widths: [CGFloat]
        var rows: [Range<Int>]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let plan = plan(for: subviews)
        onRowCountChange(plan.rows.count)
        return plan.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let plan = plan(for: subviews)
        var y = bounds.minY
        for row in plan.rows {
            var x = bounds.minX
            for index in row {
                let width = plan.widths[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: Self.tabHeight)
                )
                x += width + spacing
            }
            y += Self.tabHeight + rowSpacing
        }
    }

    private func plan(for subviews: Subviews) -> Plan {
        var widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        var rowRanges = wrappedRows(widths: widths, containerWidth: containerWidth)

        if rowRanges.count > 2 {
            let perRow = (widths.count + 1) / 2
            let available = containerWidth - spacing * CGFloat(perRow - 1)
            let uniform = max(80, min(200, available / CGFloat(perRow)))
            widths = Array(repeating: uniform, count: widths.count)
            rowRanges = [0..<perRow, perRow..<widths.count].filter { !$0.isEmpty }
        }

        let rowWidths = rowRanges.map { row in
            row.reduce(0) { $0 + widths[$1] } + spacing * CGFloat(max(0, row.count - 1))
        }
        let width = rowWidths.max() ?? 0
        let height = CGFloat(rowRanges.count) * Self.tabHeight
            + CGFloat(max(0, rowRanges.count - 1)) * rowSpacing

        return Plan(widths: widths, rows: rowRanges, size: CGSize(width: width, height: height))
    }

    private func wrappedRows(widths: [CGFloat], containerWidth: CGFloat) -> [Range<Int>] {
        var rows: [Range<Int>] = []
        var start = 0
        var x: CGFloat = 0

        for index in widths.indices {
            let needed = index == start ? widths[index] : x + spacing + widths[index]
            if index > start && needed > containerWidth {
                rows.append(start..<index)
                start = index
                x = widths[index]
            } else {
                x = needed
            }
        }
        if !widths.isEmpty {
            rows.append(start..<widths.count)
        }
        return rows
    }
}

/// SwiftUI lays the tab strip's document view out 52pt taller than the strip
/// itself (the titlebar's safe area leaks into it). That leftover vertical
/// range lets a two-finger scroll push the tabs out of view, and they stay
/// out because the overscroll is a real offset, not a bounce. The strip is
/// horizontal-only, so pin the clip view to y = 0 and drop vertical bounce.
private struct TabVerticalScrollLock: NSViewRepresentable {
    func makeNSView(context: Context) -> LockView {
        LockView()
    }

    func updateNSView(_ view: LockView, context: Context) {
        view.lockIfNeeded()
    }

    final class LockView: NSView {
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lockIfNeeded()
        }

        func lockIfNeeded() {
            guard let enclosing = enclosingScrollView else { return }
            guard scrollView !== enclosing else { return }

            scrollView = enclosing
            enclosing.hasVerticalScroller = false
            enclosing.verticalScrollElasticity = NSScrollView.Elasticity.none

            let clipView = enclosing.contentView
            clipView.postsBoundsChangedNotifications = true
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.resetVerticalOffset()
            }
        }

        private func resetVerticalOffset() {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            guard abs(clipView.bounds.origin.y) > 0.5 else { return }
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: 0))
            scrollView.reflectScrolledClipView(clipView)
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }
    }
}
