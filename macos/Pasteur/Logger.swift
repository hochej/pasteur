import Foundation

enum Logger {
    static var enabled = false
    private static let queue = DispatchQueue(label: "pasteur.logger")
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let logURL: URL = {
        let fileManager = FileManager.default
        let logsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("Pasteur.log")
    }()

    static func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        queue.async {
            append(line)
        }
        if enabled {
            print(message)
        }
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer {
            try? handle.close()
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Ignore logging failures.
        }
    }
}
