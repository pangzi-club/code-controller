import Foundation
import os

/// App-wide logging with two sinks: unified logging (Console.app / `log show`)
/// and a plain-text file under the app's `Library/Logs` — inside the sandbox
/// container for the .app — that survives crashes and needs no tooling. Use
/// the category that matches the work being done.
public struct Log {
    public static let app = Log(category: "app")
    public static let files = Log(category: "files")
    public static let window = Log(category: "window")

    private static let subsystem = AppInfo.bundleID
    private static let sink = LogFileSink()

    /// Logs the launch banner and the paths a bug report needs. Call once,
    /// before the first window appears.
    public static func bootstrap() {
        app.notice("Launch \(AppInfo.displayName) \(AppInfo.version) (\(AppInfo.build)) — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        app.notice("Bundle: \(Bundle.main.bundlePath)")
        app.notice("Sandbox: \(sandboxDescription)")
        app.notice("UserDefaults domain: \(AppInfo.bundleID)")
        app.notice("Log file: \(sink.fileURL.path)")
    }

    private static var sandboxDescription: String {
        if let container = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] {
            return "container \(container)"
        }
        return "none (not sandboxed)"
    }

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case error = "ERROR"
    }

    let category: String
    private let logger: Logger

    private init(category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    func debug(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        write(.debug, message, file: file, line: line)
    }

    func info(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        write(.info, message, file: file, line: line)
    }

    func notice(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        write(.notice, message, file: file, line: line)
    }

    func error(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        write(.error, message, file: file, line: line)
    }

    private func write(_ level: Level, _ message: String, file: StaticString, line: UInt) {
        // `.public` keeps the payload readable in `log show`; this is local
        // diagnostic output, not user input.
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        Self.sink.write(
            level: level.rawValue,
            category: category,
            message: message,
            source: "\(file):\(line)",
            synchronous: level == .error
        )
    }
}

/// Appends log lines to a file on a serial queue. The previous session is
/// rotated to `app.log.1` at launch when the file exceeds `maxBytes`.
final class LogFileSink: @unchecked Sendable {
    static let maxBytes = 2 * 1024 * 1024

    let fileURL: URL
    private let maxBytes: Int
    private let queue: DispatchQueue
    private let formatter: DateFormatter
    private var handle: FileHandle?

    convenience init() {
        // Store tests log too; keep their output out of the real app log.
        if Self.isTestProcess {
            self.init(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(AppInfo.displayName)-test-logs", isDirectory: true))
            return
        }
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
        self.init(directory: library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppInfo.displayName, isDirectory: true))
    }

    private static var isTestProcess: Bool {
        let name = ProcessInfo.processInfo.processName
        return name == "swiftpm-testing-helper" || name == "xctest"
    }

    init(
        directory: URL,
        fileName: String = "app.log",
        maxBytes: Int = LogFileSink.maxBytes
    ) {
        self.maxBytes = maxBytes
        fileURL = directory.appendingPathComponent(fileName)
        queue = DispatchQueue(label: "\(AppInfo.bundleID).log-file", qos: .utility)
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        rotateIfNeeded()
    }

    /// `synchronous` is used for errors so they reach disk before the app
    /// can trap.
    func write(
        level: String,
        category: String,
        message: String,
        source: String,
        at date: Date = Date(),
        synchronous: Bool = false
    ) {
        let line = "\(formatter.string(from: date)) [\(level)] \(category): \(message)  (\(source))\n"
        if synchronous {
            queue.sync { append(line) }
        } else {
            queue.async { self.append(line) }
        }
    }

    /// Blocks until queued lines have been written.
    func flush() {
        queue.sync {}
    }

    private func append(_ line: String) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
        }
        guard let handle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Drop the handle; the next line retries opening the file.
            self.handle = nil
        }
    }

    private func rotateIfNeeded() {
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > maxBytes else { return }
        let backup = fileURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: fileURL, to: backup)
    }
}
