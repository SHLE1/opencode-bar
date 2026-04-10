import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "CLIService")

/// Handles CLI binary install and uninstall using AppleScript with admin privileges.
enum CLIService {
    static let installPath = "/usr/local/bin/opencodebar"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    // MARK: - Install

    /// Copies the CLI binary from the app bundle to /usr/local/bin with admin privileges.
    /// Returns nil on success, or an error message on failure.
    @MainActor
    static func install() -> String? {
        let cliURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/opencodebar-cli")
        let cliPath = cliURL.path

        guard FileManager.default.fileExists(atPath: cliPath) else {
            logger.error("CLI binary not found in app bundle at \(cliPath)")
            return "CLI binary not found in app bundle. Please reinstall the app."
        }

        let escapedCliPath = cliPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set cliPath to "\(escapedCliPath)"
        do shell script "mkdir -p /usr/local/bin && cp " & quoted form of cliPath & " /usr/local/bin/opencodebar && chmod +x /usr/local/bin/opencodebar" with administrator privileges
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            logger.error("Failed to create AppleScript object for CLI install")
            return "Failed to create installation script."
        }

        scriptObject.executeAndReturnError(&error)

        if let error = error {
            let desc = error.description
            logger.error("CLI installation failed: \(desc)")
            return "Failed to install CLI: \(desc)"
        }

        logger.info("CLI installed successfully to /usr/local/bin/opencodebar")
        return nil
    }

    // MARK: - Uninstall

    /// Removes the CLI binary from /usr/local/bin with admin privileges.
    /// Returns nil on success, or an error message on failure.
    @MainActor
    static func uninstall() -> String? {
        let script = """
        do shell script "rm -f /usr/local/bin/opencodebar" with administrator privileges
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            logger.error("Failed to create AppleScript object for CLI uninstall")
            return "Failed to create uninstall script."
        }

        scriptObject.executeAndReturnError(&error)

        if let error = error {
            let desc = error.description
            logger.error("CLI uninstallation failed: \(desc)")
            return "Failed to uninstall CLI: \(desc)"
        }

        logger.info("CLI uninstalled from /usr/local/bin/opencodebar")
        return nil
    }
}
