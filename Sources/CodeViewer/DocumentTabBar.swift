import SwiftUI

/// Horizontal tab strip for the open documents of one workspace.
struct DocumentTabBar: View {
    let tabs: [DocumentTab]
    let selectedTabID: DocumentTab.ID?
    let onSelect: (DocumentTab) -> Void
    let onClose: (DocumentTab) -> Void

    @State private var hoveredTabID: DocumentTab.ID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        tabView(tab)
                            .id(tab.id)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 46)
                .background(TabVerticalScrollLock())
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selectedTabID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: 46)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabView(_ tab: DocumentTab) -> some View {
        let isSelected = tab.id == selectedTabID
        let isHovered = hoveredTabID == tab.id
        let showsCloseButton = isSelected || isHovered

        return HStack(spacing: 4) {
            Button {
                onSelect(tab)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: FileIcon.symbolName(for: tab.url, isDirectory: false))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(tab.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 80, maxWidth: 200, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

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
        .padding(.vertical, 4)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.09)
                    : isHovered ? Color.primary.opacity(0.045)
                    : Color.clear)
        )
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
                FileOpener.reveal(tab.url)
            } label: {
                l10n("Show in Finder")
            }
        }
        .help(tab.url.abbreviatedPath)
    }
}

/// SwiftUI lays the tab strip's document view out 52pt taller than the 46pt
/// strip (the titlebar's safe area leaks into it). That leftover vertical
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
