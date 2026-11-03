import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @State private var workspaces = WorkspaceStore()
    @State private var sessions = WorkspaceSessions()
    @State private var selectedWorkspaceID: Workspace.ID?
    @State private var session: WorkspaceSession?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var chromeStripHeight: CGFloat = 28
    @State private var isFullScreen = false
    @State private var isChoosingWorkspace = false
    @State private var keyMonitor: Any?

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                store: workspaces,
                selection: $selectedWorkspaceID,
                session: session,
                topPadding: isFullScreen ? 8 : max(chromeStripHeight, 28) + 8,
                onSelect: select,
                onAdd: presentWorkspacePicker,
                onRemove: removeWorkspace,
                onDropURL: addWorkspace,
                onShowDiff: { session?.requestDiff = GitDiffRequest(url: $0) }
            )
            // Removes the system sidebar toggle; its toolbar row would add a
            // 52pt strip above the content we no longer have room for.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(pageColor)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateChromeStrip(geometry.safeAreaInsets.top)
                    }
                    .onChange(of: geometry.safeAreaInsets.top) { _, height in
                        updateChromeStrip(height)
                    }
            }
        )
        .background(WindowChrome(isFullScreen: $isFullScreen))
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleSidebar()
        }
        .onAppear {
            installTabKeyMonitor()
            selectInitialWorkspaceIfNeeded()
        }
        .fileImporter(
            isPresented: $isChoosingWorkspace,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                addWorkspace(url)
            case .failure(let error):
                Log.files.error("Workspace picker failed: \(error.localizedDescription)")
            }
        }
    }

    private var pageColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    @ViewBuilder
    private var detail: some View {
        if let workspace = selectedWorkspace, let session {
            WorkspaceDetailView(
                workspace: workspace,
                session: session,
                sidebarLeadingInset: columnVisibility == .detailOnly ? 78 : 0
            )
        } else {
            PlaceholderView(addWorkspace: presentWorkspacePicker)
        }
    }

    private var selectedWorkspace: Workspace? {
        workspaces.workspaces.first { $0.id == selectedWorkspaceID }
    }

    private func selectInitialWorkspaceIfNeeded() {
        guard session == nil, let first = workspaces.workspaces.first else { return }
        select(first)
    }

    private func select(_ workspace: Workspace) {
        let newSession = sessions.session(for: workspace)
        selectedWorkspaceID = workspace.id
        session = newSession
        Task { await newSession.loadIfNeeded() }
    }

    private func addWorkspace(_ url: URL) {
        guard let workspace = workspaces.add(url) else { return }
        select(workspace)
    }

    private func removeWorkspace(_ workspace: Workspace) {
        let wasSelected = selectedWorkspaceID == workspace.id
        sessions.remove(workspace)
        workspaces.remove(workspace)
        guard wasSelected else { return }

        session = nil
        selectedWorkspaceID = nil
        if let first = workspaces.workspaces.first {
            select(first)
        }
    }

    private func presentWorkspacePicker() {
        isChoosingWorkspace = true
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// Local key monitor for tab commands: ⌘W always closes a tab — with no
    /// tabs open it deliberately does nothing, so it never surprises by
    /// closing the whole window (use the traffic light or ⌘⇧W for that).
    /// ⌘1…⌘9 select the tab at that position. Runs only while the main
    /// window is key, so Settings keeps its own system shortcuts.
    ///
    /// Keys match by ANSI keycode, and only ⇧⌃⌥ are rejected as extra
    /// modifiers: caps lock stamps `.alphaShift` on real key events and
    /// uppercases the characters, so a strict flags equality or a `"w"`
    /// character match silently misses a physical ⌘W and the system closes
    /// the window instead.
    private func installTabKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let relevant = event.modifierFlags.intersection([.shift, .control, .option, .command])
            guard MainWindowTracker.isCurrentKey,
                  event.window === NSApp.keyWindow,
                  relevant == .command else {
                return event
            }

            let digitByANSIKeycode: [UInt16: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
            ]
            switch event.keyCode {
            case 13:  // W
                NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
                return nil
            case let code where digitByANSIKeycode[code] != nil:
                let digit = digitByANSIKeycode[code]!
                NotificationCenter.default.post(
                    name: .selectTab,
                    object: nil,
                    userInfo: ["index": digit - 1]
                )
                return nil
            default:
                return event
            }
        }
    }

    /// The window has no toolbar, so the top safe area is just the traffic-light
    /// strip. It can report 0 while full screen, so the sidebar falls back to
    /// the 28pt titlebar height instead of collapsing onto the buttons.
    private func updateChromeStrip(_ height: CGFloat) {
        guard height > 0.5, abs(height - chromeStripHeight) > 0.5 else { return }
        chromeStripHeight = height
    }
}

// MARK: - Detail

private struct WorkspaceDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    let workspace: Workspace
    let session: WorkspaceSession
    /// Room for the traffic lights when the sidebar is collapsed and the
    /// content starts at the window's leading edge.
    let sidebarLeadingInset: CGFloat

    private var title: String {
        session.selectedTab?.name ?? workspace.name
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                codePane
                    .accessibilityHidden(hasOverlay)
                    .allowsHitTesting(!hasOverlay)
                overlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(title)
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorkspace)) { _ in
            Task { await session.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            guard let selectedTab = session.selectedTab else { return }
            session.close(selectedTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTab)) { note in
            guard let index = note.userInfo?["index"] as? Int,
                  session.tabs.indices.contains(index) else { return }
            session.select(session.tabs[index])
        }
        .sheet(item: diffRequestBinding) { request in
            GitDiffSheet(
                request: request,
                root: session.git.repositoryRoot,
                colorScheme: colorScheme
            )
        }
    }

    /// Bridges the session's optional diff request to the sheet's Identifiable
    /// item binding; dismissal clears it again.
    private var diffRequestBinding: Binding<GitDiffRequest?> {
        Binding(
            get: { session.requestDiff },
            set: { session.requestDiff = $0 }
        )
    }

    /// The window has no toolbar: tabs and actions live in one strip at the
    /// very top of the content, level with the traffic lights.
    private var topBar: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if session.tabs.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    DocumentTabBar(
                        tabs: session.tabs,
                        selectedTabID: session.selectedTabID,
                        git: session.git,
                        onSelect: { session.select($0) },
                        onClose: { session.close($0) },
                        onShowDiff: { session.requestDiff = GitDiffRequest(url: $0.url) }
                    )
                }
            }
            // Collapsed sidebar: keep the tabs clear of the traffic lights,
            // which move over the detail column.
            .padding(.leading, sidebarLeadingInset)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// The pool stays mounted for the lifetime of the workspace detail view so
    /// switching tabs (or to a binary file) never tears down the text views.
    /// Passing optionals keeps this a single view identity; branching between
    /// two CodePane values would recreate the coordinator and drop the pool.
    private var codePane: some View {
        CodePane(
            tabID: textSelection?.tabID,
            text: textSelection?.text,
            documentID: textSelection?.documentID,
            language: textSelection?.language,
            theme: settings.resolvedHighlightTheme(for: colorScheme),
            font: settings.editorFont
        )
    }

    private var textSelection: (tabID: String, text: String, documentID: String, language: String?)? {
        guard let tab = session.selectedTab,
              case .text(let document) = tab.document.state,
              !document.text.isEmpty else {
            return nil
        }
        return (
            tab.id,
            document.text,
            tab.document.versionID,
            SyntaxLanguageMapper.highlightLanguage(forExtension: tab.url.pathExtension)
        )
    }

    /// True while a status/loading view covers the code pane. The pane stays
    /// mounted to keep its pool, but stale text must not be focusable or
    /// readable by assistive technologies.
    private var hasOverlay: Bool {
        textSelection == nil
    }

    @ViewBuilder
    private var overlay: some View {
        if session.tabs.isEmpty {
            StatusView(icon: "doc.text", message: l10n("Select a file to view"))
        } else if let tab = session.selectedTab {
            switch tab.document.state {
            case .empty:
                StatusView(icon: "doc.text", message: l10n("Select a file to view"))
            case .loading:
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text(let document):
                if document.text.isEmpty {
                    StatusView(icon: "doc", message: l10n("This file is empty"))
                }
            case .binary:
                StatusView(
                    icon: "doc.zipper",
                    message: l10n("Binary file"),
                    detail: l10n("This file can't be displayed as text.")
                )
            case .tooLarge(let byteSize):
                StatusView(
                    icon: "doc",
                    message: l10n("File too large"),
                    detail: l10n(
                        "This file is %@ and too large to display.",
                        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
                    )
                )
            case .failed:
                StatusView(
                    icon: "exclamationmark.triangle",
                    message: l10n("Couldn't read this file. It may have been moved or deleted.")
                )
            }
        }
    }
}

private struct PlaceholderView: View {
    let addWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(24)
                .background(Circle().fill(Color.primary.opacity(0.04)))
            l10n("Add a workspace to get started")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Button(action: addWorkspace) {
                l10n("Add Workspace…")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct StatusView: View {
    let icon: String
    let message: Text
    var detail: Text?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            message
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail {
                detail
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Window chrome

/// Tracks full screen and keeps the window toolbar hidden while in it.
///
/// `.toolbar(.hidden, for: .windowToolbar)` only empties the titlebar: the top
/// safe area keeps the toolbar height and, before macOS 26, the full-screen
/// auto-hide overlay loses its traffic lights. `NSToolbar.isVisible` collapses
/// the safe area and leaves the buttons alone.
private struct WindowChrome: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            MainWindowTracker.set(window)
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
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.setToolbar(window, visible: false)
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
            setToolbar(window, visible: !isActuallyFullScreen)
            publish(isActuallyFullScreen)
        }

        /// The toolbar can come back on its own during the transition, and it may
        /// not exist yet on the first pass, so every sync re-asserts the state.
        private func setToolbar(_ window: NSWindow, visible: Bool) {
            guard let toolbar = window.toolbar, toolbar.isVisible != visible else { return }
            toolbar.isVisible = visible
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

#if DEBUG
#Preview {
    ContentView()
        .frame(width: 1080, height: 720)
        .background(Color(nsColor: .controlBackgroundColor))
}
#endif
