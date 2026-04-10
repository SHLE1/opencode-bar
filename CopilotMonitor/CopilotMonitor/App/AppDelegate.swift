import AppKit
import SwiftUI
import Sparkle
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var statusBarController: StatusBarController!
    private(set) var updaterController: SPUStandardUpdaterController!
    private var settingsWindow: NSWindow?

    @objc func checkForUpdates() {
        logger.info("⌨️ [Keyboard] ⌘U Check for Updates triggered")
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(self)
    }

    @objc func openSettingsWindow() {
        logger.info("⌨️ [Keyboard] Settings window triggered")
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 520, height: 440))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMigrationHelper.shared.checkAndMigrateIfNeeded() {
            return
        }
        
        AppMigrationHelper.shared.cleanupLegacyBundlesIfNeeded()
        
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        
        configureAutomaticUpdates()
        statusBarController = StatusBarController()
        closeAllWindows()
    }
    
    private func configureAutomaticUpdates() {
        let updater = updaterController.updater
        let desiredCheckInterval: TimeInterval = 21600

        // Sparkle persists user preferences for update behavior.
        // Do not override these values on launch.
        if updater.updateCheckInterval != desiredCheckInterval {
            updater.updateCheckInterval = desiredCheckInterval
            logger.info("🔄 [Sparkle] Update check interval updated to 6h (\(desiredCheckInterval)s)")
        }

        let checksEnabled = updater.automaticallyChecksForUpdates
        let downloadsEnabled = updater.automaticallyDownloadsUpdates
        let checkInterval = updater.updateCheckInterval
        
        logger.info("🔄 [Sparkle] Auto-update state loaded: checks=\(checksEnabled), downloads=\(downloadsEnabled), interval=\(checkInterval)s")
    }

    private func closeAllWindows() {
        for window in NSApp.windows where window.title.contains("Settings") {
            window.close()
        }
    }

    // MARK: - SPUUpdaterDelegate
    
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("🔄 [Sparkle] App will relaunch after update")
    }
    
    nonisolated func updaterDidRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("✅ [Sparkle] App relaunched successfully")
    }
}
