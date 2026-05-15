import Foundation
import os.log

/// Shared debug logging utility for structured debug output.
enum DebugLogger {
    private static let logger = Logger(subsystem: "com.opencodeproviders", category: "Debug")

    static func log(_ category: String, _ message: String) {
        logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
    }
}
