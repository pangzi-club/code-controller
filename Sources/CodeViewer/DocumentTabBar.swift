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
                .frame(height: 34)
            }
            .onChange(of: selectedTabID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: 34)
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
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 60, maxWidth: 180, alignment: .leading)
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
        .frame(height: 26)
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
