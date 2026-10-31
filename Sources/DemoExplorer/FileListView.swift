import SwiftUI

struct InlineWindowToolbar<Trailing: View>: View {
    let title: String?
    let toggleSidebar: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            toolbarButton(
                systemName: "sidebar.leading",
                help: "Toggle Sidebar",
                action: toggleSidebar
            )

            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            trailing
        }
        // A 16pt glyph centered in a 28pt button needs 14pt outer padding
        // for its visible edge to match the list card's 20pt inset.
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toolbarButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n(help))
        .focusEffectDisabled()
    }
}

struct FileListView: View {
    let folder: Folder
    let showsFullScreenToolbar: Bool
    let toggleSidebar: () -> Void

    @State private var items: [FileItem] = []
    @State private var loadFailed = false
    @State private var hoveredItemID: String?

    init(
        folder: Folder,
        showsFullScreenToolbar: Bool = false,
        toggleSidebar: @escaping () -> Void = {}
    ) {
        self.folder = folder
        self.showsFullScreenToolbar = showsFullScreenToolbar
        self.toggleSidebar = toggleSidebar
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsFullScreenToolbar {
                InlineWindowToolbar(title: folder.name, toggleSidebar: toggleSidebar) {
                    HStack(spacing: 8) {
                        inlineToolbarButton(
                            systemName: "arrow.up.forward.app",
                            help: "Show in Finder"
                        ) {
                            FileOpener.reveal(folder.url)
                        }
                        inlineToolbarButton(systemName: "arrow.clockwise", help: "Refresh") {
                            reload()
                        }
                    }
                }
            }

            if !loadFailed {
                HStack {
                    l10n("%lld items", items.count)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text(folder.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            // hiddenTitleBar leaves no trailing flexible region; without this
            // the primary actions pack next to the title.
            ToolbarItem {
                Spacer()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    FileOpener.reveal(folder.url)
                } label: {
                    Label {
                        l10n("Show in Finder")
                    } icon: {
                        Image(systemName: "arrow.up.forward.app")
                            .frame(width: 16, height: 16)
                    }
                }
                Button {
                    reload()
                } label: {
                    Label {
                        l10n("Refresh")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 16, height: 16)
                    }
                }
                // Toolbar adds 8pt; match the visible glyph to the card's 20pt inset.
                .padding(.trailing, 7)
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var content: some View {
        if loadFailed {
            statusView(
                icon: "exclamationmark.triangle",
                text: "Couldn't read this folder. It may have been moved or deleted."
            )
            .background(cardShape)
        } else if items.isEmpty {
            statusView(icon: "tray", text: "This folder is empty")
                .background(cardShape)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .background(cardShape)
        }
    }

    private func reload() {
        if let loaded = FileLoader.load(from: folder.url) {
            items = loaded
            loadFailed = false
        } else {
            items = []
            loadFailed = true
        }
    }

    private func inlineToolbarButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n(help))
        .focusEffectDisabled()
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }

    private func statusView(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.secondary.opacity(0.4))
            l10n(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: FileItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle(for: item))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hoveredItemID == item.id ? Color.primary.opacity(0.035) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hoveredItemID = $0 ? item.id : nil }
        .onTapGesture(count: 2) { FileOpener.open(item.url) }
        .contextMenu {
            Button(action: { FileOpener.open(item.url) }) {
                l10n("Open")
            }
            Button(action: { FileOpener.reveal(item.url) }) {
                l10n("Show in Finder")
            }
        }
    }

    private func subtitle(for item: FileItem) -> String {
        if item.isDirectory { return l10nString("Folder") }
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

#if DEBUG
#Preview {
    FileListView(
        folder: Folder(id: UUID(), url: PreviewFixtures.sampleFolder)
    )
    .frame(width: 600, height: 500)
}
#endif
