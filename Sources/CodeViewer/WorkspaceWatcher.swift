import Foundation

/// Watches one directory subtree with FSEvents and coalesces bursts of
/// change events into a single debounced callback on the main actor. One
/// instance per workspace session, started when the session's tree loads.
final class WorkspaceWatcher {
    private let rootPath: String
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "workspace-watcher")

    private var stream: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    /// Balances the `passRetained` in the stream context.
    private var retainedSelf: Unmanaged<WorkspaceWatcher>?

    /// Latency passed to FSEvents; the real coalescing happens below.
    private static let streamLatency = 0.3
    private static let debounceInterval = 0.5

    init(root: URL, onChange: @MainActor @escaping () -> Void) {
        rootPath = root.path
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, eventCount, eventPaths, _, _ in
                let watcher = Unmanaged<WorkspaceWatcher>
                    .fromOpaque(clientInfo!)
                    .takeUnretainedValue()
                watcher.recordEvents(count: eventCount, pathsPointer: eventPaths)
            },
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.streamLatency,
            flags
        ) else {
            retained.release()
            retainedSelf = nil
            Log.files.error("FSEventStreamCreate failed for \(rootPath)")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        debounceTimer?.cancel()
        debounceTimer = nil
        retainedSelf?.release()
        retainedSelf = nil
    }

    deinit {
        stop()
    }

    /// Called on the watcher queue for every batch of file events.
    private func recordEvents(count: Int, pathsPointer: UnsafeMutableRawPointer) {
        let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
        // One relevant path in the batch is enough to refresh; the tree and
        // git status reads are cheap compared to missing an update.
        guard paths.contains(where: { !Self.isNoise($0) }) else { return }
        scheduleDebounce()
    }

    /// VCS metadata and Finder noise never trigger a refresh.
    static func isNoise(_ path: String) -> Bool {
        path.hasSuffix("/.git") || path.contains("/.git/") || path.hasSuffix(".DS_Store")
    }

    private func scheduleDebounce() {
        queue.async { [weak self] in
            guard let self else { return }
            debounceTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.debounceInterval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [onChange] in
                    onChange()
                }
            }
            debounceTimer = timer
            timer.resume()
        }
    }
}
