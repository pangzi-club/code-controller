import SwiftUI

/// Sidebar: a workspace menu followed by the selected workspace's file tree.
struct SidebarView: View {
    let store: WorkspaceStore
    @Binding var selection: Workspace.ID?
    let session: WorkspaceSession?
    let topPadding: CGFloat
    let onSelect: (Workspace) -> Void
    let onAdd: () -> Void
    let onRemove: (Workspace) -> Void
    let onDropURL: (URL) -> Void

    @State private var dropTargeted = false

    private var selectedWorkspace: Workspace? {
        store.workspaces.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.workspaces.isEmpty {
                emptyState
                    .padding(.top, topPadding)
            } else {
                switcher
                    .padding(.horizontal, 10)
                    .padding(.top, topPadding)
                    .padding(.bottom, 4)

                if let session {
                    FileTreeView(tree: session.tree, document: session.document)
                } else {
                    Spacer()
                }
            }
        }
        // The sidebar is drawn under the transparent titlebar; reserve the
        // traffic-light strip in the header padding instead of letting
        // NavigationSplitView add its own (doubled) top inset. No background is
        // painted here: the split view's native translucent sidebar material
        // shows through.
        .ignoresSafeArea(.container, edges: .top)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            onDropURL(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
                    .padding(5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var switcher: some View {
        VStack(alignment: .leading, spacing: 3) {
            Menu {
                ForEach(store.workspaces) { workspace in
                    Button {
                        onSelect(workspace)
                    } label: {
                        if workspace.id == selection {
                            Label(workspace.name, systemImage: "checkmark")
                        } else {
                            Text(workspace.name)
                        }
                    }
                }

                Divider()

                Button(action: onAdd) {
                    Label(l10nString("Add Workspace…"), systemImage: "plus")
                }

                if let selectedWorkspace {
                    Divider()
                    Button(role: .destructive) {
                        onRemove(selectedWorkspace)
                    } label: {
                        Label(l10nString("Remove Workspace"), systemImage: "trash")
                    }
                }
            } label: {
                switcherLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)

            if let selectedWorkspace {
                Text(selectedWorkspace.url.abbreviatedPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 38)
            }
        }
    }

    private var switcherLabel: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(WorkspacePalette.color(for: selectedWorkspace?.url.path ?? "").gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(
                    color: WorkspacePalette.color(for: selectedWorkspace?.url.path ?? "").opacity(0.4),
                    radius: 2,
                    y: 1
                )

            Text(selectedWorkspace?.name ?? l10nString("Workspace"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            l10n("Add a workspace to get started")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                l10n("Add Workspace…")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Stable workspace icon colors across launches. `hashValue` changes per
/// launch, so use djb2 over the path instead.
enum WorkspacePalette {
    static let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .cyan, .indigo, .brown]

    static func color(for path: String) -> Color {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}
