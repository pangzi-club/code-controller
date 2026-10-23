import SwiftUI

/// What the detail pane currently shows: a sidebar folder or the settings page.
enum SidebarSelection: Hashable {
    case folder(UUID)
    case settings
}

public struct ContentView: View {
    @StateObject private var store = FolderStore()
    @State private var selection: SidebarSelection?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailContent
        }
        .onAppear {
            if selection == nil {
                selection = store.folders.first.map { .folder($0.id) }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .settings:
            SettingsView()
        case .folder(let id):
            if let folder = store.folders.first(where: { $0.id == id }) {
                FileListView(folder: folder)
                    .id(folder.id)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        PlaceholderView(hasFolders: !store.folders.isEmpty) {
            addFolderAndSelect()
        }
    }

    private func addFolderAndSelect() {
        if let url = FolderPicker.chooseFolder(), let folder = store.add(url) {
            selection = .folder(folder.id)
        }
    }
}

private struct PlaceholderView: View {
    let hasFolders: Bool
    let addFolder: () -> Void

    private var message: String {
        hasFolders ? "Select a folder on the left" : "Add a folder to get started"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(24)
                .background(Circle().fill(Color.primary.opacity(0.04)))
            l10n(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            if !hasFolders {
                Button(action: addFolder) {
                    l10n("Add Folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @ObservedObject var store: FolderStore
    @Binding var selection: SidebarSelection?

    @State private var hoveredFolderID: UUID?
    @State private var addHovered = false
    @State private var settingsHovered = false
    @State private var dropTargeted = false

    private var selectedFolderID: UUID? {
        if case .folder(let id) = selection { return id }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                l10n("Folders")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if !store.folders.isEmpty {
                    Text("\(store.folders.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.folders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.secondary.opacity(0.4))
                    l10n("Click the button below to add a folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.folders) { folder in
                            SidebarRowView(
                                folder: folder,
                                isSelected: folder.id == selectedFolderID,
                                isHovered: folder.id == hoveredFolderID
                            )
                            .onTapGesture { selection = .folder(folder.id) }
                            .onHover { hovering in
                                hoveredFolderID = hovering ? folder.id : nil
                            }
                            .contextMenu {
                                Button(action: { FileOpener.reveal(folder.url) }) {
                                    l10n("Show in Finder")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    if selectedFolderID == folder.id { selection = nil }
                                    store.remove(folder)
                                } label: {
                                    l10n("Remove")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            HStack(spacing: 8) {
                addButton
                settingsButton
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            if let folder = store.add(url) {
                selection = .folder(folder.id)
            }
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

    private var addButton: some View {
        Button {
            if let url = FolderPicker.chooseFolder(), let folder = store.add(url) {
                selection = .folder(folder.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                l10n("Add Folder")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(addHovered ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(addHovered ? 0.35 : 0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { addHovered = $0 }
    }

    private var settingsButton: some View {
        let isActive = selection == .settings
        return Button {
            selection = .settings
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? .accentColor : settingsHovered ? .accentColor : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(settingsHovered || isActive ? 0.35 : 0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { settingsHovered = $0 }
        .help(l10nString("Settings"))
    }
}

private struct SidebarRowView: View {
    let folder: Folder
    let isSelected: Bool
    let isHovered: Bool

    private var tint: Color { FolderPalette.color(for: folder.url.path) }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(color: tint.opacity(0.4), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(folder.url.abbreviatedPath)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

enum FolderPalette {
    static let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .cyan, .indigo, .brown]

    /// djb2 hash: `hashValue` changes on every launch, this keeps each folder's
    /// color stable across launches.
    static func color(for path: String) -> Color {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return colors[Int(hash % UInt64(colors.count))]
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

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
        .frame(width: 1080, height: 720)
        .toolbarBackground(Color(nsColor: .controlBackgroundColor), for: .windowToolbar)
}
