import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the detail pane currently shows: the selected sidebar folder.
enum SidebarSelection: Hashable {
    case folder(UUID)
}

public struct ContentView: View {
    @StateObject private var store = FolderStore()
    @State private var selection: SidebarSelection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var toolbarStripHeight: CGFloat = 52
    @State private var isChoosingFolder = false
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
            SidebarView(store: store, selection: $selection, onAddFolder: presentFolderPicker)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailContent
                .overlay(alignment: .top) {
                    pageColor
                        .frame(height: toolbarStripHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(.container, edges: .top)
                        .allowsHitTesting(false)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background(pageColor)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateToolbarStrip(geometry.safeAreaInsets.top)
                    }
                    .onChange(of: geometry.safeAreaInsets.top) { height in
                        updateToolbarStrip(height)
                    }
            }
        )
        .onAppear {
            if selection == nil {
                selection = store.folders.first.map { .folder($0.id) }
            }
            dropSidebarToggleFocus()
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                if let folder = store.add(url) {
                    selection = .folder(folder.id)
                }
            case .failure(let error):
                Log.files.error("Folder picker failed: \(error.localizedDescription)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            openWindow(id: "settings")
        }
    }

    private var pageColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Keeps the page-colored strip above the detail column in sync with the
    /// window toolbar; the sidebar must stay transparent all the way to the
    /// traffic lights, so the toolbar background itself is hidden.
    private func updateToolbarStrip(_ height: CGFloat) {
        let clamped = max(0, height)
        guard abs(clamped - toolbarStripHeight) > 0.5 else { return }
        toolbarStripHeight = clamped
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
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
            presentFolderPicker()
        }
    }

    private func presentFolderPicker() {
        isChoosingFolder = true
    }

    /// The toolbar sidebar toggle keeps keyboard focus — and with it a
    /// permanent focus ring — once clicked (or once the window appears),
    /// because nothing in the detail pane is focusable to take over. Hand
    /// focus back to the window whenever the toggle is used.
    private func dropSidebarToggleFocus() {
        DispatchQueue.main.async {
            let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
            window?.makeFirstResponder(nil)
        }
    }

    /// Routes NavigationSplitView's column writes through a custom binding so
    /// the focus drop above runs on every sidebar toggle, including the
    /// ⌥⌘S shortcut.
    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnVisibility },
            set: {
                columnVisibility = $0
                dropSidebarToggleFocus()
            }
        )
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
    let onAddFolder: () -> Void

    @State private var hoveredFolderID: UUID?
    @State private var addHovered = false
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
            .padding(.top, 44)
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

            addButton
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        // The sidebar is drawn under the transparent titlebar; reserve the
        // traffic-light strip in the header padding instead of letting
        // NavigationSplitView add its own (doubled) top inset. No background is
        // painted here: the split view's native translucent sidebar material
        // shows the desktop through.
        .ignoresSafeArea(.container, edges: .top)
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
        Button(action: onAddFolder) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(addHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                l10n("Add Folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(addHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { addHovered = $0 }
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
        .frame(width: 1080, height: 720)
        .background(Color(nsColor: .controlBackgroundColor))
}
