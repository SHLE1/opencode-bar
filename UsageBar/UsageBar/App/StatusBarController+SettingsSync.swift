import AppKit
import ServiceManagement

extension StatusBarController {
    func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRefreshIntervalChange),
            name: AppPreferences.refreshIntervalDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePredictionPeriodChange),
            name: AppPreferences.predictionPeriodDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEnabledProvidersChange),
            name: AppPreferences.enabledProvidersDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCriticalBadgeChange),
            name: AppPreferences.criticalBadgeDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowProviderIconChange),
            name: AppPreferences.showProviderIconDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMultiProviderProvidersChange),
            name: AppPreferences.multiProviderProvidersDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCodexStatusBarAccountChange),
            name: AppPreferences.codexStatusBarAccountDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCodexStatusBarWindowChange),
            name: AppPreferences.codexStatusBarWindowDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppLanguageChange),
            name: AppPreferences.appLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSubscriptionChange),
            name: AppPreferences.subscriptionDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCopilotAddOnChange),
            name: AppPreferences.copilotAddOnDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStatusBarOrderChange),
            name: AppPreferences.statusBarOrderDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePayAsYouGoOrderChange),
            name: AppPreferences.payAsYouGoOrderDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePrivacyModeChange),
            name: AppPreferences.privacyModeDidChange, object: nil
        )
    }

    @objc func handleRefreshIntervalChange() {
        debugLog("Settings: refreshInterval changed")
        restartRefreshTimer()
        updateRefreshIntervalMenu()
    }

    @objc func handlePredictionPeriodChange() {
        debugLog("Settings: predictionPeriod changed")
        updatePredictionPeriodMenu()
        updateHistorySubmenu()
        updateMultiProviderMenu()
    }

    @objc func handleEnabledProvidersChange() {
        debugLog("Settings: enabledProviders changed")
        updateEnabledProvidersMenu()
        updateStatusBarDisplayMenuState()
        updateStatusBarText()
        refreshClicked()
    }

    @objc func handleCriticalBadgeChange() {
        debugLog("Settings: criticalBadge changed")
        updateStatusBarText()
    }

    @objc func handleShowProviderIconChange() {
        debugLog("Settings: showProviderIcon changed")
        updateStatusBarText()
    }

    @objc func handleMultiProviderProvidersChange() {
        debugLog("Settings: multiProviderProviders changed")
        updateStatusBarDisplayMenuState()
        updateStatusBarText()
    }

    @objc func handleCodexStatusBarAccountChange() {
        debugLog("Settings: codexStatusBarAccount changed")
        updateStatusBarText()
        updateMultiProviderMenu()
    }

    @objc func handleCodexStatusBarWindowChange() {
        debugLog("Settings: codexStatusBarWindow changed")
        updateStatusBarText()
        updateMultiProviderMenu()
    }

    @objc func handleAppLanguageChange() {
        debugLog("Settings: appLanguage changed")
        setupMenu()
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    @objc func handleSubscriptionChange() {
        debugLog("Settings: subscription changed")
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    @objc func handleCopilotAddOnChange() {
        debugLog("Settings: Copilot Add-on toggled")
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    @objc func handleStatusBarOrderChange() {
        debugLog("Settings: status bar subscription order changed")
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    @objc func handlePayAsYouGoOrderChange() {
        debugLog("Settings: pay-as-you-go order changed")
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    @objc func handlePrivacyModeChange() {
        debugLog("Settings: privacyMode changed")
        updateMultiProviderMenu()
        updateStatusBarText()
    }

    func updateLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
