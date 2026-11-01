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
    @State private var isFullScreen = false
    @State private var isChoosingFolder = false

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                store: store,
                selection: $selection,
                topPadding: isFullScreen ? 8 : toolbarStripHeight + 8,
                onAddFolder: presentFolderPicker
            )
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailContent
                .overlay(alignment: .top) {
                    if !isFullScreen {
                        pageColor
                            .frame(height: toolbarStripHeight)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .ignoresSafeArea(.container, edges: .top)
                            .allowsHitTesting(false)
                    }
                }
                // Before macOS 26 hiding the window toolbar only empties it, the
                // top safe area stays at the toolbar height, so the detail column
                // has to ignore it to match the sidebar's full-screen inset.
                .ignoresSafeArea(.container, edges: isFullScreen ? .top : [])
        }
        .navigationSplitViewStyle(.balanced)
        .background(pageColor)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label {
                        l10n("Toggle Sidebar")
                    } icon: {
                        Image(systemName: "sidebar.leading")
                    }
                }
                .labelStyle(.iconOnly)
                .help(l10n("Toggle Sidebar"))
                .focusEffectDisabled()
                // Toolbar adds 5pt; this puts the visible glyph on the list card's 20pt inset.
                .padding(.leading, 8)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateToolbarStrip(geometry.safeAreaInsets.top)
                    }
                    .onChange(of: geometry.safeAreaInsets.top) { _, height in
                        updateToolbarStrip(height)
                    }
            }
        )
        .background(WindowFullScreenReader(isFullScreen: $isFullScreen))
        .onAppear {
            if selection == nil {
                selection = store.folders.first.map { .folder($0.id) }
            }
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
    }

    private var pageColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Keeps the page-colored strip above the detail column in sync with the
    /// transparent toolbar.
    private func updateToolbarStrip(_ height: CGFloat) {
        // Retain the last windowed height while full screen removes the safe
        // area, so the strip is ready in the same frame as the toolbar returns.
        guard height > 0.5, abs(height - toolbarStripHeight) > 0.5 else { return }
        toolbarStripHeight = height
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

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct WindowFullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowTrackingView, context: Context) {
        context.coordinator.isFullScreen = $isFullScreen
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ view: WindowTrackingView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.attach(to: nil)
    }

    final class Coordinator {
        var isFullScreen: Binding<Bool>

        private weak var window: NSWindow?
        private var styleMaskObservation: NSKeyValueObservation?
        private var observations: [NSObjectProtocol] = []
        private var isExitingFullScreen = false

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        deinit {
            removeObservations()
        }

        func attach(to window: NSWindow?) {
            if self.window === window {
                if let window {
                    sync(to: window)
                }
                return
            }
            removeObservations()
            isExitingFullScreen = false
            self.window = window

            guard let window else { return }

            sync(to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                if let window {
                    self?.sync(to: window)
                }
            }

            styleMaskObservation = window.observe(\.styleMask, options: [.new]) { [weak self, weak window] _, _ in
                DispatchQueue.main.async {
                    if let window {
                        self?.sync(to: window)
                    }
                }
            }

            let center = NotificationCenter.default
            observations.append(center.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isExitingFullScreen = false
                self?.publish(true)
            })
            observations.append(center.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isExitingFullScreen = true
            })
            observations.append(center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isExitingFullScreen = false
                self?.publish(false)
            })
        }

        private func sync(to window: NSWindow) {
            let isActuallyFullScreen = window.styleMask.contains(.fullScreen)
            guard isActuallyFullScreen || !isExitingFullScreen else { return }
            publish(isActuallyFullScreen)
        }

        private func publish(_ value: Bool) {
            guard isFullScreen.wrappedValue != value else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isFullScreen.wrappedValue != value else { return }
                self.isFullScreen.wrappedValue = value
            }
        }

        private func removeObservations() {
            styleMaskObservation = nil
            let center = NotificationCenter.default
            observations.forEach(center.removeObserver)
            observations.removeAll()
        }
    }

    final class WindowTrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
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
    let topPadding: CGFloat
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
            .frame(height: 20)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
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
                            let isSelected = folder.id == selectedFolderID
                            Button {
                                selection = .folder(folder.id)
                            } label: {
                                SidebarRowView(
                                    folder: folder,
                                    isSelected: isSelected,
                                    isHovered: folder.id == hoveredFolderID
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

#Preview {
    ContentView()
        .frame(width: 1080, height: 720)
        .background(Color(nsColor: .controlBackgroundColor))
}
