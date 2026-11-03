import SwiftUI

/// Flattened tree rows for the selected workspace.
struct FileTreeView: View {
    let tree: FileTreeStore
    let document: DocumentStore

    var body: some View {
        Group {
            if tree.isLoadingRoot && tree.rootNodes.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tree.rootFailed {
                statusView(
                    icon: "exclamationmark.triangle",
                    message: "Couldn't read this workspace. It may have been moved or deleted."
                )
            } else if tree.rows.isEmpty {
                statusView(icon: "tray", message: "This workspace is empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(tree.rows) { row in
                            FileTreeRowView(row: row, tree: tree, document: document)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func statusView(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            l10n(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileTreeRowView: View {
    let row: FileTreeRow
    let tree: FileTreeStore
    let document: DocumentStore

    @State private var isHovered = false

    private var isSelected: Bool {
        !row.node.isDirectory && row.node.url == document.url
    }

    private var isExpanded: Bool {
        tree.expanded.contains(row.node.id)
    }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 3) {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 13, height: 1)
                chevron
                icon
                Text(row.node.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if tree.loading.contains(row.node.id) {
                    ProgressView()
                        .controlSize(.mini)
                } else if tree.failed.contains(row.node.id) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(row.node.url.abbreviatedPath)
        .contextMenu {
            if !row.node.isDirectory {
                Button {
                    FileOpener.open(row.node.url)
                } label: {
                    l10n("Open")
                }
            }
            Button {
                FileOpener.reveal(row.node.url)
            } label: {
                l10n("Show in Finder")
            }
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var chevron: some View {
        Group {
            if row.node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: 10, height: 10)
    }

    private var icon: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11))
            .foregroundStyle(isSelected ? Color.white : iconColor)
            .frame(width: 16)
    }

    private var iconColor: Color {
        row.node.isDirectory ? .accentColor : .secondary
    }

    private var symbolName: String {
        if row.node.isDirectory { return "folder" }
        switch row.node.url.pathExtension.lowercased() {
        case "json", "yaml", "yml", "toml", "plist", "xml", "entitlements", "xcconfig", "lock":
            return "curlybraces"
        case "md", "markdown", "txt", "rtf", "log":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tiff", "pdf":
            return "photo"
        case "swift", "js", "jsx", "ts", "tsx", "mjs", "cjs", "py", "rb", "go", "rs",
             "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "cs", "php",
             "sh", "zsh", "bash", "fish", "lua", "pl", "r", "sql", "html", "css",
             "scss", "less", "vue", "svelte", "dart", "ex", "exs", "erl", "hs", "clj",
             "scala":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    private func activate() {
        if row.node.isDirectory {
            Task { await tree.toggle(row.node) }
        } else {
            document.open(row.node)
        }
    }
}

#if DEBUG
private struct FileTreePreview: View {
    @State private var session = WorkspaceSession(
        workspace: Workspace(url: PreviewFixtures.sampleWorkspace)
    )

    var body: some View {
        FileTreeView(tree: session.tree, document: session.document)
            .frame(width: 260, height: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .task { await session.loadIfNeeded() }
    }
}

#Preview {
    FileTreePreview()
}
#endif
