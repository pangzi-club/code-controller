import Foundation
import Testing
@testable import DemoExplorer

@Suite
struct LogTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("log-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("file sink appends lines with level, category and source")
    func appendsFormattedLines() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sink = LogFileSink(directory: directory, maxBytes: 1 << 20)
        sink.write(level: "INFO", category: "test", message: "hello", source: "LogTests.swift:10")
        sink.write(level: "ERROR", category: "test", message: "boom", source: "LogTests.swift:11")
        sink.flush()

        let text = try String(contentsOf: sink.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].range(
            of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[INFO\] test: hello  \(LogTests\.swift:10\)$"#,
            options: .regularExpression
        ) != nil)
        #expect(lines[1].range(
            of: #"^.* \[ERROR\] test: boom  \(LogTests\.swift:11\)$"#,
            options: .regularExpression
        ) != nil)
    }

    @Test("oversized log rotates to app.log.1 on the next launch")
    func rotatesOversizedFile() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = LogFileSink(directory: directory, maxBytes: 64)
        first.write(
            level: "INFO",
            category: "test",
            message: String(repeating: "x", count: 120),
            source: "LogTests.swift:20"
        )
        first.flush()

        let second = LogFileSink(directory: directory, maxBytes: 64)
        second.write(level: "INFO", category: "test", message: "fresh", source: "LogTests.swift:21")
        second.flush()

        let backup = first.fileURL.appendingPathExtension("1")
        let rotated = try String(contentsOf: backup, encoding: .utf8)
        let current = try String(contentsOf: second.fileURL, encoding: .utf8)
        #expect(rotated.contains("xxxxxxxx"))
        #expect(!current.contains("xxxx"))
        #expect(current.contains("fresh"))
    }
}
