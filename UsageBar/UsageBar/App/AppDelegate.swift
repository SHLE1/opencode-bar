import AppKit
import SwiftUI
import Sparkle
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("UsageBarSettingsWindow")
    var statusBarController: StatusBarController!
    private(set) var updaterController: SPUStandardUpdaterController!
    private var settingsWindow: NSWindow?
    private var localizationObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?

    @objc func checkForUpdates() {
        logger.info("[Keyboard] Command-U Check for Updates triggered")
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(self)
    }

    @objc func openSettingsWindow() {
        logger.info("[Keyboard] Settings window triggered")
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = settingsWindowIdentifier
        window.title = L("Settings")
        window.appearance = AppPreferences.shared.appAppearanceMode.applicationAppearance
        window.setContentSize(NSSize(width: 840, height: 560))
        window.minSize = NSSize(width: 760, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false

        // Restore saved frame or center on first open
        window.setFrameAutosaveName("UsageBarSettingsWindow")
        if !window.setFrameUsingName("UsageBarSettingsWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        logger.info("Applied standard settings window chrome with frame autosave")
        logger.debug("Opened settings window at \(Int(window.frame.width))x\(Int(window.frame.height))")

        settingsWindow = window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMigrationHelper.shared.checkAndMigrateIfNeeded() {
            return
        }
        
        AppMigrationHelper.shared.cleanupLegacyBundlesIfNeeded()
        AppMigrationHelper.shared.migrateOpenCodeZenSettings()
        
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        localizationObserver = NotificationCenter.default.addObserver(
            forName: AppPreferences.appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settingsWindow?.title = L("Settings")
            }
        }

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: AppPreferences.appAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppAppearance()
            }
        }
        
        configureAutomaticUpdates()
        applyAppAppearance()
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
            logger.info("[Sparkle] Update check interval updated to 6h (\(desiredCheckInterval)s)")
        }

        let checksEnabled = updater.automaticallyChecksForUpdates
        let downloadsEnabled = updater.automaticallyDownloadsUpdates
        let checkInterval = updater.updateCheckInterval
        
        logger.info("[Sparkle] Auto-update state loaded: checks=\(checksEnabled), downloads=\(downloadsEnabled), interval=\(checkInterval)s")
    }

    private func closeAllWindows() {
        for window in NSApp.windows where window.identifier == settingsWindowIdentifier {
            window.close()
        }
    }

    private func applyAppAppearance() {
        let appearance = AppPreferences.shared.appAppearanceMode.applicationAppearance
        NSApp.appearance = appearance
        settingsWindow?.appearance = appearance
        settingsWindow?.contentView?.needsLayout = true
        logger.info("Applied app appearance mode \(AppPreferences.shared.appAppearanceMode.rawValue, privacy: .public)")
    }

    // MARK: - SPUUpdaterDelegate
    
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("[Sparkle] App will relaunch after update")
    }
    
    private nonisolated func updaterDidRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("[Sparkle] App relaunched successfully")
    }
}
