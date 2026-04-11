import Foundation

/// Shared debug logging utility for file-based debug output.
/// Consolidates the identical `debugLog()` pattern used across multiple components.
enum DebugLogger {

    /// Appends a timestamped message to the specified log file.
    /// Fails silently if the file cannot be written.
    static func log(_ category: String, _ message: String, to path: String = "/tmp/provider_debug.log") {
        #if DEBUG
        let msg = "[\(Date())] \(category): \(message)\n"
        guard let data = msg.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        #endif
    }
}
