import AppKit
import SwiftUI
import ServiceManagement
import WebKit
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "StatusBarController")

private enum StatusBarMetricKind {
    case cost
    case usage
}

private enum UsageDisplayWindowPriority: Int, CaseIterable {
    case weekly = 0
    case monthly = 1
    case daily = 2
    case hourly = 3
    case fallback = 4
}

private struct UsagePercentCandidate {
    let percent: Double
    let priority: UsageDisplayWindowPriority
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isMainMenuTracking = true
        debugLog("menuWillOpen: tracking enabled")
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isMainMenuTracking = false
        debugLog("menuDidClose: tracking disabled")
        flushDeferredUIUpdatesIfNeeded()
    }
}

private struct StatusBarProviderSnapshot: Equatable {
    let value: Double
    let kind: StatusBarMetricKind
}

private struct RecentChangeCandidate: Equatable {
    let identifier: ProviderIdentifier
    let kind: StatusBarMetricKind
    let delta: Double
    let observedAt: Date
}

enum UsageFetcherError: LocalizedError {
    case noCustomerId
    case noUsageData
    case invalidJSResult
    case parsingFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noCustomerId:
            return "Customer ID not found"
        case .noUsageData:
            return "Usage data not found"
        case .invalidJSResult:
            return "Invalid JS result"
        case .parsingFailed(let detail):
            return "Parsing failed: \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    var statusItem: NSStatusItem?
    var statusBarIconView: StatusBarIconView?
    var multiProviderBarView: MultiProviderBarView?
    var multiProviderBarMenu: NSMenu!
    var menu: NSMenu!
    var launchAtLoginItem: NSMenuItem!
    var installCLIItem: NSMenuItem!
    var refreshIntervalMenu: NSMenu!
    var criticalBadgeMenuItem: NSMenuItem!
    var showProviderNameMenuItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var initialRefreshTask: Task<Void, Never>?
    var isMainMenuTracking = false
    var hasDeferredMenuRebuild = false
    var hasDeferredStatusBarRefresh = false

    var currentUsage: CopilotUsage?
    private var lastFetchTime: Date?
    private var isFetching = false

    // History fetch properties
    private var historyFetchTimer: Timer?
    private var customerId: String?

    // History properties (for Copilot provider via CopilotHistoryService)
    private var usageHistory: UsageHistory?
    private var lastHistoryFetchResult: HistoryFetchResult = .none

    // History UI properties
    var historySubmenu: NSMenu!
    var historyMenuItem: NSMenuItem!
    var predictionPeriodMenu: NSMenu!

    // Multi-provider properties
    var providerResults: [ProviderIdentifier: ProviderResult] = [:]
    var loadingProviders: Set<ProviderIdentifier> = []
    var enabledProvidersMenu: NSMenu!
    var lastProviderErrors: [ProviderIdentifier: String] = [:]
    var viewErrorDetailsItem: NSMenuItem!
    var orphanedSubscriptionKeys: [String] = []
    var orphanedSubscriptionTotal: Double = 0
    private let criticalUsageThreshold: Double = 90.0
    private let alertFirstUsageThreshold: Double = 100.0
    private let recentChangeMaxAge: TimeInterval = 3 * 60 * 60
    private var previousProviderSnapshots: [ProviderIdentifier: StatusBarProviderSnapshot] = [:]
    private var recentChangeCandidate: RecentChangeCandidate?

    private var usagePredictor: UsagePredictor {
        UsagePredictor(weights: predictionPeriod.weights)
    }

    enum HistoryFetchResult {
        case none
        case success
        case failedWithCache
        case failedNoCache
    }

    private enum GrowthEvent: String {
        case shareSnapshotClicked = "share_snapshot_clicked"
        case shareSnapshotXOpened = "share_snapshot_x_opened"
    }

    struct HistoryUIState {
        let history: UsageHistory?
        let prediction: UsagePrediction?
        let isStale: Bool
        let hasNoData: Bool
    }

    var refreshInterval: RefreshInterval {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "refreshInterval")
            return RefreshInterval(rawValue: rawValue) ?? .defaultInterval
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "refreshInterval")
            restartRefreshTimer()
            updateRefreshIntervalMenu()
        }
    }

    var predictionPeriod: PredictionPeriod {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "predictionPeriod")
            return PredictionPeriod(rawValue: rawValue) ?? .defaultPeriod
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "predictionPeriod")
            updatePredictionPeriodMenu()
            updateHistorySubmenu()
            updateMultiProviderMenu()
        }
    }

    var criticalBadgeEnabled: Bool {
        get {
            boolPreference(forKey: StatusBarDisplayPreferences.criticalBadgeKey, defaultValue: true)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: StatusBarDisplayPreferences.criticalBadgeKey)
            updateStatusBarDisplayMenuState()
            updateStatusBarText()
        }
    }

    var showProviderName: Bool {
        get {
            boolPreference(forKey: StatusBarDisplayPreferences.showProviderNameKey, defaultValue: false)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: StatusBarDisplayPreferences.showProviderNameKey)
            updateStatusBarDisplayMenuState()
            updateStatusBarText()
        }
    }

    /// Which providers to show in Multi-Provider Bar mode.
    /// Defaults to all known providers so users see something useful immediately.
    var multiProviderSelection: [ProviderIdentifier] {
        get {
            guard let saved = UserDefaults.standard.array(forKey: StatusBarDisplayPreferences.multiProviderProvidersKey) as? [String] else {
                return ProviderIdentifier.allCases
            }
            return saved.compactMap { ProviderIdentifier(rawValue: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.map { $0.rawValue }, forKey: StatusBarDisplayPreferences.multiProviderProvidersKey)
        }
    }

    private var codexStatusBarAccountSelectionKey: String? {
        get {
            AppPreferences.shared.codexStatusBarAccountSelectionKey
        }
        set {
            AppPreferences.shared.codexStatusBarAccountSelectionKey = newValue
        }
    }

    private var codexStatusBarWindowMode: CodexStatusBarWindowMode {
        get {
            AppPreferences.shared.codexStatusBarWindowMode
        }
        set {
            AppPreferences.shared.codexStatusBarWindowMode = newValue
        }
    }

    private func codexFiveHourUsedPercent(for account: ProviderAccountResult) -> Double {
        account.details?.dailyUsage ?? account.usage.usagePercentage
    }

    /// Returns the remaining percents for the Codex five-hour and weekly windows.
    /// The five-hour value always resolves to a non-nil Double; weekly is nil when no secondary usage exists.
    private func codexWindowRemainingPercents(
        for account: ProviderAccountResult
    ) -> (fiveHour: Double, weekly: Double?) {
        let fiveHour = codexRemainingPercent(from: codexFiveHourUsedPercent(for: account))
            ?? max(0.0, 100.0 - account.usage.usagePercentage)
        let weekly = codexRemainingPercent(from: account.details?.secondaryUsage)
        return (fiveHour, weekly)
    }

    private func isProviderInMultiBar(_ identifier: ProviderIdentifier) -> Bool {
        multiProviderSelection.contains(identifier)
    }

    override init() {
        super.init()
        debugLog("StatusBarController init started")

        TokenManager.shared.logDebugEnvironmentInfo()
        debugLog("Environment debug info logged")

        setupStatusItem()
        debugLog("setupStatusItem completed")
        setupMenu()
        debugLog("setupMenu completed")
        setupNotificationObservers()
        debugLog("setupNotificationObservers completed")
        startRefreshTimer()
        debugLog("startRefreshTimer completed")
        checkAndPromptGitHubStar()
        debugLog("checkAndPromptGitHubStar called")
        logger.info("Init completed")
        debugLog("Init completed")
    }

    deinit {
        refreshTimer?.invalidate()
        initialRefreshTask?.cancel()
    }

    func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    private func boolPreference(forKey key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func flushDeferredUIUpdatesIfNeeded() {
        if hasDeferredMenuRebuild {
            hasDeferredMenuRebuild = false
            debugLog("flushDeferredUIUpdatesIfNeeded: applying deferred menu rebuild")
            updateMultiProviderMenu()
            return
        }

        if hasDeferredStatusBarRefresh {
            hasDeferredStatusBarRefresh = false
            debugLog("flushDeferredUIUpdatesIfNeeded: applying deferred status bar refresh")
            updateStatusBarText()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        statusBarIconView = StatusBarIconView(frame: .zero)
        statusBarIconView?.onIntrinsicContentSizeDidChange = { [weak self] in
            self?.updateStatusItemLayout(reason: "intrinsic-size-changed")
        }
        statusBarIconView?.showLoading()

        multiProviderBarView = MultiProviderBarView(frame: .zero)
        multiProviderBarView?.onIntrinsicContentSizeDidChange = { [weak self] in
            self?.updateStatusItemLayout(reason: "multi-provider-size-changed")
        }

        attachActiveStatusBarView()
        updateStatusItemLayout(reason: "setup")
    }

    /// Detaches all status bar subviews and attaches the active status bar view.
    func attachActiveStatusBarView() {
        guard let button = statusItem?.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        button.image = nil

        if let mpv = multiProviderBarView {
            button.addSubview(mpv)
        } else if let iconView = statusBarIconView {
            button.addSubview(iconView)
        }
    }

    func updateStatusItemLayout(reason: String) {
        guard let statusItem, let button = statusItem.button else { return }
        let activeView: NSView? = multiProviderBarView ?? statusBarIconView
        guard let activeView else { return }

        let intrinsicSize = activeView.intrinsicContentSize
        let minWidth = MenuDesignToken.Dimension.iconSize + 4
        let width = max(minWidth, ceil(intrinsicSize.width))

        activeView.frame = NSRect(x: 0, y: 0, width: width, height: intrinsicSize.height)
        statusItem.length = width
        button.needsDisplay = true

        let widthText = String(format: "%.1f", width)
        let intrinsicWidthText = String(format: "%.1f", intrinsicSize.width)
        debugLog("statusIconLayout[\(reason)]: width=\(widthText), intrinsicWidth=\(intrinsicWidthText)")
        logger.debug("statusIconLayout[\(reason)]: width=\(widthText, privacy: .public)")
    }

    /// Attach the existing menu to an external NSStatusItem (for MenuBarExtraAccess bridge)
    func attachTo(_ statusItem: NSStatusItem) {
        debugLog("attachTo: called with statusItem")
        self.statusItem = statusItem
        statusItem.menu = self.menu
        statusItem.length = NSStatusItem.variableLength

        debugLog("attachTo: setting up status bar view")
        attachActiveStatusBarView()
        updateStatusItemLayout(reason: "attach")
    }

    func isProviderEnabled(_ identifier: ProviderIdentifier) -> Bool {
        let key = "provider.\(identifier.rawValue).enabled"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    var isCopilotAddOnEnabled: Bool {
        if UserDefaults.standard.object(forKey: "provider.copilot_add_on.enabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "provider.copilot_add_on.enabled")
    }

    func restartRefreshTimer() {
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        initialRefreshTask?.cancel()

        let interval = TimeInterval(refreshInterval.rawValue)
        let intervalTitle = refreshInterval.title
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            logger.info("Timer triggered (\(intervalTitle))")
            Task { @MainActor [weak self] in
                self?.triggerRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        initialRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.triggerRefresh()
        }
    }

    func triggerRefresh() {
        logger.info("triggerRefresh started")
        fetchUsage()
    }

    private func fetchUsage() {
        debugLog("fetchUsage: called")
        logger.info("fetchUsage started, isFetching: \(self.isFetching)")

        guard !isFetching else {
            debugLog("fetchUsage: already fetching, returning")
            return
        }
        isFetching = true
        if isMainMenuTracking {
            hasDeferredStatusBarRefresh = true
            debugLog("fetchUsage: menu is open, deferring loading indicator")
        } else {
            debugLog("fetchUsage: showing loading")
            statusBarIconView?.showLoading()
        }

        debugLog("fetchUsage: creating Task")
        Task { @MainActor in
            debugLog("fetchUsage Task: calling fetchMultiProviderData")
            await fetchMultiProviderData()
            debugLog("fetchUsage Task: fetchMultiProviderData completed")
            debugLog("fetchUsage Task: all done, setting isFetching=false")
            self.isFetching = false
        }
        debugLog("fetchUsage: Task created")
    }

    // MARK: - Multi-Provider Fetch

     private func fetchMultiProviderData() async {
           debugLog("fetchMultiProviderData: started")
           logger.info("[StatusBarController] fetchMultiProviderData() started")
           
           let enabledProviders = await ProviderManager.shared.getAllProviders().filter { provider in
               isProviderEnabled(provider.identifier)
           }
           debugLog("fetchMultiProviderData: enabledProviders count=\(enabledProviders.count)")
           logger.debug("[StatusBarController] enabledProviders: \(enabledProviders.map { $0.identifier.displayName }.joined(separator: ", "))")

           guard !enabledProviders.isEmpty else {
               logger.info("[StatusBarController] fetchMultiProviderData: No enabled providers, skipping")
               debugLog("fetchMultiProviderData: No enabled providers, returning")
               return
           }

           loadingProviders = Set(enabledProviders.map { $0.identifier })
           let loadingCount = loadingProviders.count
           let loadingNames = loadingProviders.map { $0.displayName }.joined(separator: ", ")
           debugLog("fetchMultiProviderData: marked \(loadingCount) providers as loading")
           logger.debug("[StatusBarController] loadingProviders set: \(loadingNames)")
           updateMultiProviderMenu()

           logger.info("[StatusBarController] fetchMultiProviderData: Calling ProviderManager.fetchAll()")
           debugLog("fetchMultiProviderData: calling ProviderManager.fetchAll()")
           let fetchResult = await ProviderManager.shared.fetchAll()
           debugLog("fetchMultiProviderData: fetchAll returned \(fetchResult.results.count) results, \(fetchResult.errors.count) errors")
           logger.info("[StatusBarController] fetchMultiProviderData: fetchAll() returned \(fetchResult.results.count) results, \(fetchResult.errors.count) errors")

           let filteredResults = fetchResult.results.filter { identifier, _ in
               isProviderEnabled(identifier)
           }
           let filteredNames = filteredResults.keys.map { $0.displayName }.joined(separator: ", ")
           debugLog("fetchMultiProviderData: filteredResults count=\(filteredResults.count)")
           logger.debug("[StatusBarController] filteredResults: \(filteredNames)")

           self.providerResults = filteredResults
            
            // Extract CopilotUsage from provider result if available
            if let copilotResult = filteredResults[.copilot],
               let details = copilotResult.details,
               let usedRequests = details.copilotUsedRequests,
               let limitRequests = details.copilotLimitRequests {
                self.currentUsage = CopilotUsage(
                    netBilledAmount: details.copilotOverageCost ?? 0.0,
                    netQuantity: details.copilotOverageRequests ?? 0.0,
                    discountQuantity: Double(usedRequests),
                    userPremiumRequestEntitlement: limitRequests,
                    filteredUserPremiumRequestEntitlement: 0,
                    copilotPlan: details.planType,
                    quotaResetDateUTC: details.copilotQuotaResetDateUTC
                )
                debugLog("fetchMultiProviderData: currentUsage set from Copilot provider - used: \(usedRequests), limit: \(limitRequests)")
                logger.info("[StatusBarController] currentUsage set from Copilot provider")
            } else {
                debugLog("fetchMultiProviderData: No Copilot data available, currentUsage not set")
            }
            
            let filteredErrors = fetchResult.errors.filter { identifier, _ in
                isProviderEnabled(identifier)
            }
            self.lastProviderErrors = filteredErrors

           for identifier in filteredResults.keys {
               loadingProviders.remove(identifier)
           }
           for identifier in filteredErrors.keys {
               loadingProviders.remove(identifier)
           }
           let remainingLoading = loadingProviders.map { $0.displayName }.joined(separator: ", ")
           debugLog("fetchMultiProviderData: cleared loading state for \(filteredResults.count) results, \(filteredErrors.count) errors")
           logger.debug("[StatusBarController] loadingProviders after clear: \(remainingLoading)")
           self.viewErrorDetailsItem.isHidden = filteredErrors.isEmpty
           debugLog("fetchMultiProviderData: viewErrorDetailsItem.isHidden = \(filteredErrors.isEmpty)")
           
           if !filteredErrors.isEmpty {
               let errorNames = filteredErrors.keys.map { $0.displayName }.joined(separator: ", ")
               debugLog("fetchMultiProviderData: errors from: \(errorNames)")
               logger.warning("[StatusBarController] Errors from providers: \(errorNames)")
           }
           debugLog("fetchMultiProviderData: calling updateMultiProviderMenu")
           logger.debug("[StatusBarController] providerResults updated, calling updateMultiProviderMenu()")
           self.updateMultiProviderMenu()
           debugLog("fetchMultiProviderData: updateMultiProviderMenu completed")
           logger.info("[StatusBarController] fetchMultiProviderData: updateMultiProviderMenu() completed")

           logger.info("[StatusBarController] fetchMultiProviderData: Completed with \(filteredResults.count) results")
           debugLog("fetchMultiProviderData: completed")
       }

    func calculatePayAsYouGoTotal(providerResults: [ProviderIdentifier: ProviderResult], copilotUsage: CopilotUsage?) -> Double {
        var total = 0.0

        if isCopilotAddOnEnabled, let copilot = copilotUsage {
            total += copilot.netBilledAmount
        }

        for (_, result) in providerResults {
            if case .payAsYouGo(_, let cost, _) = result.usage, let cost = cost {
                total += cost
            }
        }

        return total
    }

    func calculateTotalWithSubscriptions(providerResults: [ProviderIdentifier: ProviderResult], copilotUsage: CopilotUsage?) -> Double {
        let payAsYouGo = calculatePayAsYouGoTotal(providerResults: providerResults, copilotUsage: copilotUsage)
        let subscriptions = calculateVisibleSubscriptionTotal()
        return payAsYouGo + subscriptions
    }

    struct AlertProviderCandidate {
        let identifier: ProviderIdentifier
        let usedPercent: Double
    }

    private func formatCostForStatusBar(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    private func formatCostOrStatusBarBrand(_ cost: Double) -> String {
        if cost <= 0 {
            return "OC Bar"
        }
        return formatCostForStatusBar(cost)
    }

    func normalizedUsagePercent(_ percent: Double?) -> Double? {
        guard let percent, percent.isFinite else { return nil }
        return min(max(percent, 0), 999)
    }

    func dailyPercentFromDetails(_ details: DetailedUsage?) -> Double? {
        guard let details else { return nil }
        if let limit = details.limit, limit > 0, let used = details.dailyUsage {
            return (used / limit) * 100.0
        }
        return details.dailyUsage
    }

    func chutesMonthlyPercentFromDetails(_ details: DetailedUsage?) -> Double? {
        guard let details else { return nil }

        let configuredPlan = SubscriptionSettingsManager.shared.getPlan(for: .chutes)
        let configuredCapUSD = configuredPlan.isSet
            ? configuredPlan.cost * ChutesProvider.monthlyValueMultiplier
            : nil
        let capUSD = configuredCapUSD ?? details.chutesMonthlyValueCapUSD

        if let usedUSD = details.chutesMonthlyValueUsedUSD,
           let capUSD,
           capUSD > 0 {
            return min(max((usedUSD / capUSD) * 100.0, 0), 999)
        }

        return details.chutesMonthlyValueUsedPercent
    }

    private func usagePercentCandidates(
        identifier: ProviderIdentifier,
        usage: ProviderUsage,
        details: DetailedUsage?
    ) -> [UsagePercentCandidate] {
        var candidates: [UsagePercentCandidate] = []
        func add(_ percent: Double?, priority: UsageDisplayWindowPriority) {
            guard let normalized = normalizedUsagePercent(percent) else { return }
            candidates.append(UsagePercentCandidate(percent: normalized, priority: priority))
        }

        switch identifier {
        case .claude:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.sonnetUsage, priority: .weekly)
            add(details?.opusUsage, priority: .weekly)
            add(details?.extraUsageUtilizationPercent, priority: .monthly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .kimi:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .minimaxCodingPlan:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .codex:
            add(details?.secondaryUsage, priority: .weekly)
            add(details?.sparkSecondaryUsage, priority: .weekly)
            add(dailyPercentFromDetails(details), priority: .daily)
            add(details?.sparkUsage, priority: .hourly)
        case .copilot:
            if let used = details?.copilotUsedRequests,
               let limit = details?.copilotLimitRequests,
               limit > 0 {
                add((Double(used) / Double(limit)) * 100.0, priority: .monthly)
            }
            add(usage.usagePercentage, priority: .monthly)
        case .zaiCodingPlan:
            add(details?.mcpUsagePercent, priority: .monthly)
            add(details?.tokenUsagePercent, priority: .hourly)
        case .nanoGpt:
            add(details?.sevenDayUsage, priority: .weekly)
        case .chutes:
            add(chutesMonthlyPercentFromDetails(details), priority: .monthly)
            add(dailyPercentFromDetails(details), priority: .daily)
        case .synthetic:
            add(details?.fiveHourUsage, priority: .hourly)
        case .antigravity, .geminiCLI, .openRouter, .openCode:
            break
        }

        add(usage.usagePercentage, priority: .fallback)
        return candidates
    }

    private func preferredUsedPercent(
        identifier: ProviderIdentifier,
        usage: ProviderUsage,
        details: DetailedUsage?
    ) -> Double? {
        let candidates = usagePercentCandidates(identifier: identifier, usage: usage, details: details)
        guard let selectedPriority = candidates.map(\.priority.rawValue).min() else {
            return nil
        }

        return candidates
            .filter { $0.priority.rawValue == selectedPriority }
            .map(\.percent)
            .max()
    }

    private func codexSelectionKey(for account: ProviderAccountResult) -> String {
        if let selectionKey = account.selectionKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectionKey.isEmpty {
            return selectionKey
        }

        return TokenManager.shared.codexStatusBarSelectionKey(
            email: account.details?.email,
            accountId: account.accountId,
            externalUsageAccountId: nil,
            authSource: account.details?.authSource ?? "",
            index: account.accountIndex
        )
    }

    func resolvedCodexStatusBarAccount(from result: ProviderResult, persistCorrection: Bool = true) -> ProviderAccountResult? {
        guard let accounts = result.accounts, !accounts.isEmpty else {
            if persistCorrection, codexStatusBarAccountSelectionKey != nil {
                codexStatusBarAccountSelectionKey = nil
            }
            return nil
        }

        let savedSelectionKey = codexStatusBarAccountSelectionKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedSelectionKey, !savedSelectionKey.isEmpty,
           let selectedAccount = accounts.first(where: { codexSelectionKey(for: $0) == savedSelectionKey }) {
            return selectedAccount
        }

        let fallbackAccount = accounts[0]
        let fallbackSelectionKey = codexSelectionKey(for: fallbackAccount)
        if persistCorrection, codexStatusBarAccountSelectionKey != fallbackSelectionKey {
            codexStatusBarAccountSelectionKey = fallbackSelectionKey
            debugLog("resolvedCodexStatusBarAccount: corrected selection to \(fallbackSelectionKey)")
        }
        return fallbackAccount
    }

    private func codexRemainingPercent(
        from usedPercent: Double?
    ) -> Double? {
        guard let usedPercent = normalizedUsagePercent(usedPercent) else { return nil }
        return max(0.0, 100.0 - usedPercent)
    }

    func codexStatusBarText(
        for account: ProviderAccountResult,
        compact: Bool
    ) -> String {
        let (fiveHour, weekly) = codexWindowRemainingPercents(for: account)

        switch codexStatusBarWindowMode {
        case .fiveHourOnly:
            return UsagePercentDisplayFormatter.string(from: fiveHour)
        case .weeklyOnly:
            return UsagePercentDisplayFormatter.string(from: weekly ?? fiveHour)
        case .fiveHourAndWeekly:
            guard let weekly else {
                return UsagePercentDisplayFormatter.string(from: fiveHour)
            }
            if compact {
                let fiveHourCompact = String(UsagePercentDisplayFormatter.wholePercent(from: fiveHour))
                let weeklyCompact = String(UsagePercentDisplayFormatter.wholePercent(from: weekly))
                return "\(fiveHourCompact)/\(weeklyCompact)"
            }
            return "\(UsagePercentDisplayFormatter.string(from: fiveHour)), \(UsagePercentDisplayFormatter.string(from: weekly))"
        }
    }

    func codexStatusBarEmphasisRemainingPercent(for account: ProviderAccountResult) -> Double {
        let (fiveHour, weekly) = codexWindowRemainingPercents(for: account)

        switch codexStatusBarWindowMode {
        case .fiveHourOnly:
            return fiveHour
        case .weeklyOnly:
            return weekly ?? fiveHour
        case .fiveHourAndWeekly:
            guard let weekly else {
                return fiveHour
            }
            return min(fiveHour, weekly)
        }
    }

    /// Collects all UsagePercentCandidates from all accounts for a provider,
    /// then applies the global priority rule: pick the highest-priority window
    /// across ALL accounts, then return the max percent within that window.
    /// This prevents a high hourly value from one account beating a lower weekly
    /// value from another account.
    func preferredUsedPercentForStatusBar(identifier: ProviderIdentifier, result: ProviderResult) -> Double? {
        if identifier == .codex,
           let selectedAccount = resolvedCodexStatusBarAccount(from: result) {
            let fiveHourUsedPercent = normalizedUsagePercent(codexFiveHourUsedPercent(for: selectedAccount))
            let weeklyUsedPercent = normalizedUsagePercent(selectedAccount.details?.secondaryUsage)

            switch codexStatusBarWindowMode {
            case .fiveHourOnly:
                return fiveHourUsedPercent
            case .weeklyOnly:
                return weeklyUsedPercent ?? fiveHourUsedPercent
            case .fiveHourAndWeekly:
                return [fiveHourUsedPercent, weeklyUsedPercent].compactMap { $0 }.max()
            }
        }

        var allCandidates: [UsagePercentCandidate] = []

        // Main result candidates
        if case .quotaBased = result.usage {
            allCandidates.append(contentsOf:
                usagePercentCandidates(identifier: identifier, usage: result.usage, details: result.details)
            )
        }

        // Sub-account candidates
        if let accounts = result.accounts {
            for account in accounts {
                guard case .quotaBased = account.usage else { continue }
                allCandidates.append(contentsOf:
                    usagePercentCandidates(identifier: identifier, usage: account.usage, details: account.details)
                )
            }
        }

        // Gemini CLI special case: add as fallback priority since these don't have window metadata
        if identifier == .geminiCLI, let geminiAccounts = result.details?.geminiAccounts {
            for account in geminiAccounts {
                if let normalized = normalizedUsagePercent(100.0 - account.remainingPercentage) {
                    allCandidates.append(UsagePercentCandidate(percent: normalized, priority: .fallback))
                }
            }
        }

        // Apply global priority rule: pick highest priority (lowest rawValue),
        // then max percent within that priority
        guard let selectedPriority = allCandidates.map(\.priority.rawValue).min() else {
            return nil
        }

        return allCandidates
            .filter { $0.priority.rawValue == selectedPriority }
            .map(\.percent)
            .max()
    }

    private func usedPercentsForChangeDetection(identifier: ProviderIdentifier, result: ProviderResult) -> [Double] {
        var usedPercents: [Double] = []

        func appendMetrics(usage: ProviderUsage, details: DetailedUsage?) {
            guard case .quotaBased = usage else { return }
            if let percent = normalizedUsagePercent(usage.usagePercentage) {
                usedPercents.append(percent)
            }

            if let details {
                let extraPercents: [Double?] = [
                    details.fiveHourUsage,
                    details.sevenDayUsage,
                    details.sonnetUsage,
                    details.opusUsage,
                    details.secondaryUsage,
                    details.sparkUsage,
                    details.sparkSecondaryUsage,
                    details.tokenUsagePercent,
                    details.mcpUsagePercent
                ]
                for percent in extraPercents {
                    if let normalized = normalizedUsagePercent(percent) {
                        usedPercents.append(normalized)
                    }
                }
            }
        }

        if identifier != .codex {
            appendMetrics(usage: result.usage, details: result.details)
        }

        if identifier == .codex, let selectedAccount = resolvedCodexStatusBarAccount(from: result) {
            appendMetrics(usage: selectedAccount.usage, details: selectedAccount.details)
        } else if let accounts = result.accounts {
            for account in accounts {
                appendMetrics(usage: account.usage, details: account.details)
            }
        }

        if identifier == .geminiCLI, let geminiAccounts = result.details?.geminiAccounts {
            for account in geminiAccounts {
                if let percent = normalizedUsagePercent(100.0 - account.remainingPercentage) {
                    usedPercents.append(percent)
                }
            }
        }

        return usedPercents
    }

    private func statusSnapshot(for identifier: ProviderIdentifier, result: ProviderResult) -> StatusBarProviderSnapshot? {
        switch result.usage {
        case .payAsYouGo(_, let cost, _):
            return StatusBarProviderSnapshot(
                value: max(0.0, cost ?? 0.0),
                kind: .cost
            )
        case .quotaBased:
            let cappedPercents = usedPercentsForChangeDetection(identifier: identifier, result: result).map { min($0, 100.0) }
            // Use aggregate quota usage for change detection so non-max windows/accounts can still trigger updates.
            let aggregatePercent = cappedPercents.isEmpty
                ? min(max(result.usage.usagePercentage, 0.0), 100.0)
                : cappedPercents.reduce(0.0, +)
            return StatusBarProviderSnapshot(value: max(0.0, aggregatePercent), kind: .usage)
        }
    }

    private func refreshRecentChangeCandidate() {
        var currentSnapshots: [ProviderIdentifier: StatusBarProviderSnapshot] = [:]
        for (identifier, result) in providerResults {
            guard isProviderEnabled(identifier) else { continue }
            guard case .quotaBased = result.usage else { continue }
            guard let snapshot = statusSnapshot(for: identifier, result: result) else { continue }
            currentSnapshots[identifier] = snapshot
        }

        guard !currentSnapshots.isEmpty else {
            previousProviderSnapshots = [:]
            recentChangeCandidate = nil
            debugLog("refreshRecentChangeCandidate: no snapshots")
            return
        }

        if previousProviderSnapshots.isEmpty {
            previousProviderSnapshots = currentSnapshots
            debugLog("refreshRecentChangeCandidate: baseline snapshots saved")
            return
        }

        if currentSnapshots == previousProviderSnapshots {
            if let existing = recentChangeCandidate, currentSnapshots[existing.identifier] == nil {
                recentChangeCandidate = nil
            }
            debugLog("refreshRecentChangeCandidate: snapshots unchanged, keeping previous candidate")
            return
        }

        var bestCandidate: RecentChangeCandidate?
        for (identifier, newSnapshot) in currentSnapshots {
            guard let oldSnapshot = previousProviderSnapshots[identifier],
                  oldSnapshot.kind == newSnapshot.kind else {
                continue
            }

            let delta = newSnapshot.value - oldSnapshot.value
            let absDelta = abs(delta)
            let minThreshold: Double = (newSnapshot.kind == .cost) ? 0.01 : 0.01
            guard absDelta >= minThreshold else { continue }

            if bestCandidate == nil || absDelta > abs(bestCandidate!.delta) {
                bestCandidate = RecentChangeCandidate(
                    identifier: identifier,
                    kind: newSnapshot.kind,
                    delta: delta,
                    observedAt: Date()
                )
            }
        }

        previousProviderSnapshots = currentSnapshots
        if let bestCandidate {
            recentChangeCandidate = bestCandidate
        } else if let existing = recentChangeCandidate, currentSnapshots[existing.identifier] == nil {
            recentChangeCandidate = nil
        }

        if let bestCandidate {
            debugLog(
                "refreshRecentChangeCandidate: provider=\(bestCandidate.identifier.displayName), kind=\(bestCandidate.kind), delta=\(String(format: "%.2f", bestCandidate.delta))"
            )
        } else {
            debugLog("refreshRecentChangeCandidate: no significant change, keeping previous candidate")
        }
    }

    private func quotaAlertCandidates() -> [AlertProviderCandidate] {
        var candidates: [AlertProviderCandidate] = []
        for (identifier, result) in providerResults {
            guard isProviderEnabled(identifier) else { continue }
            guard case .quotaBased = result.usage else { continue }
            guard let usedPercent = preferredUsedPercentForStatusBar(identifier: identifier, result: result) else { continue }
            candidates.append(AlertProviderCandidate(identifier: identifier, usedPercent: usedPercent))
        }
        return candidates
    }

    func mostCriticalProvider(minUsagePercent: Double) -> AlertProviderCandidate? {
        quotaAlertCandidates()
            .filter { $0.usedPercent >= minUsagePercent }
            .max(by: { $0.usedPercent < $1.usedPercent })
    }

    private func singleEnabledQuotaProvider(atOrAbove threshold: Double) -> AlertProviderCandidate? {
        let candidates = quotaAlertCandidates()
        guard candidates.count == 1, let candidate = candidates.first, candidate.usedPercent >= threshold else {
            return nil
        }
        return candidate
    }

    func mostCriticalProvider() -> AlertProviderCandidate? {
        mostCriticalProvider(minUsagePercent: criticalUsageThreshold)
    }

    private func formatRecentChangeText(_ candidate: RecentChangeCandidate) -> String {
        guard let result = providerResults[candidate.identifier] else {
            return "--"
        }

        if candidate.identifier == .codex,
           let selectedAccount = resolvedCodexStatusBarAccount(from: result) {
            return codexStatusBarText(for: selectedAccount, compact: false)
        }

        switch result.usage {
        case .payAsYouGo(_, let cost, _):
            return formatCostForStatusBar(cost ?? 0.0)
        case .quotaBased:
            let percent = preferredUsedPercentForStatusBar(identifier: candidate.identifier, result: result)
                ?? preferredUsedPercent(
                    identifier: candidate.identifier,
                    usage: result.usage,
                    details: result.details
                )
                ?? min(max(result.usage.usagePercentage, 0.0), 999.0)
            let remaining = max(0.0, 100.0 - percent)
            logger.debug(
                "Recent change percent resolved: provider=\(candidate.identifier.displayName), usedPercent=\(String(format: "%.2f", percent)), remainingPercent=\(String(format: "%.2f", remaining))"
            )
            return UsagePercentDisplayFormatter.string(from: remaining)
        }
    }

    private func formatAlertText(identifier: ProviderIdentifier, usedPercent: Double) -> String {
        if identifier == .codex,
           let result = providerResults[identifier],
           let selectedAccount = resolvedCodexStatusBarAccount(from: result) {
            return codexStatusBarText(for: selectedAccount, compact: false)
        }

        let remaining = max(0.0, 100.0 - usedPercent)
        return UsagePercentDisplayFormatter.string(from: remaining)
    }

    private func formatProviderForStatusBar(identifier: ProviderIdentifier, result: ProviderResult) -> String {
        switch result.usage {
        case .payAsYouGo(_, let cost, _):
            let costText = formatCostForStatusBar(cost ?? 0)
            return costText
        case .quotaBased:
            if identifier == .codex,
               let selectedAccount = resolvedCodexStatusBarAccount(from: result) {
                return codexStatusBarText(for: selectedAccount, compact: false)
            }
            let maxUsedPercent = preferredUsedPercentForStatusBar(identifier: identifier, result: result) ?? result.usage.usagePercentage
            let remainingPercent = max(0.0, 100.0 - maxUsedPercent)
            return UsagePercentDisplayFormatter.string(from: remainingPercent)
        }
    }

    func iconForProvider(_ identifier: ProviderIdentifier) -> NSImage? {
        let image = identifier.menuIconAssetName.flatMap { NSImage(named: $0) }
            ?? NSImage(
                systemSymbolName: identifier.menuIconSymbolName,
                accessibilityDescription: identifier.displayName
            )

        if image == nil {
            debugLog("iconForProvider: missing icon for \(identifier.displayName)")
        }

         // Keep consistent icon sizing and make Gemini slightly larger.
         if let image = image {
             let iconSize = identifier == .geminiCLI
                 ? MenuDesignToken.Dimension.geminiIconSize
                 : MenuDesignToken.Dimension.iconSize
             image.size = NSSize(width: iconSize, height: iconSize)
         }
         return image
     }

     func tintedImage(_ image: NSImage?, color: NSColor) -> NSImage? {
         guard let image = image else { return nil }
         guard let tinted = image.copy() as? NSImage else { return image }
         tinted.lockFocus()
         color.set()
         let rect = NSRect(origin: .zero, size: tinted.size)
         rect.fill(using: .sourceAtop)
         tinted.unlockFocus()
         return tinted
     }

     // MARK: - Custom Menu Item Views

    /// System-first section header: uses attributedTitle instead of a custom view.
    func createSectionHeaderItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    /// System-first disabled menu item: uses standard NSMenuItem instead of a custom view.
    func createDisabledMenuItem(text: String, icon: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let icon = icon {
            item.image = icon
        }
        return item
    }

    func createDisabledLabelView(
        text: String,
        icon: NSImage? = nil,
        font: NSFont? = nil,
        underline: Bool = false,
        monospaced: Bool = false,
        multiline: Bool = false,
        indent: CGFloat = 0,
        textColor: NSColor = .secondaryLabelColor
    ) -> NSView {
        var leadingOffset: CGFloat = MenuDesignToken.Spacing.leadingOffset + indent
        let menuWidth: CGFloat = MenuDesignToken.Dimension.menuWidth
        let labelFont = font ?? (monospaced ? NSFont.monospacedDigitSystemFont(ofSize: MenuDesignToken.Dimension.fontSize, weight: .regular) : NSFont.systemFont(ofSize: MenuDesignToken.Dimension.fontSize))

        if icon != nil {
            leadingOffset = MenuDesignToken.Spacing.leadingWithIcon
        }

        let availableWidth = menuWidth - leadingOffset - MenuDesignToken.Spacing.trailingMargin
        var viewHeight: CGFloat = MenuDesignToken.Dimension.itemHeight

        if multiline {
            let size = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            let rect = (text as NSString).boundingRect(
                with: size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: labelFont]
            )
            viewHeight = max(22, ceil(rect.height) + 8)
        }

        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: viewHeight))

        if let icon = icon {
            let iconY = multiline ? viewHeight - 19 : 3
            let imageView = NSImageView(frame: NSRect(x: 14, y: iconY, width: 16, height: 16))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            view.addSubview(imageView)
        }

        let label = NSTextField(labelWithString: "")

        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: labelFont
        ]

        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        label.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        label.translatesAutoresizingMaskIntoConstraints = false

        if multiline {
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = availableWidth
        }

        view.addSubview(label)

        if multiline {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingOffset),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
            ])
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingOffset),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        return view
    }

    private func evalJSONString(_ js: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)

        if let json = result as? String {
            return json
        } else if let dict = result as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) {
            return json
        } else {
            throw UsageFetcherError.invalidJSResult
        }
    }

    @objc func refreshClicked() {
        logger.info("[Keyboard] Command-R Refresh triggered")
        debugLog("refreshClicked: Command-R shortcut activated")
        fetchUsage()
    }

    @objc private func openBillingClicked() {
        if let url = URL(string: "https://github.com/settings/billing/premium_requests_usage") { NSWorkspace.shared.open(url) }
    }

    @objc func openGitHub() {
        logger.info("Opening GitHub repository")
        if let url = URL(string: "https://github.com/SHLE1/usage-bar") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showAboutPanel() {
        logger.info("Showing standard About panel")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func shareUsageSnapshotClicked() {
        logger.info("Share Usage Snapshot triggered")
        debugLog("shareUsageSnapshotClicked: started")
        trackGrowthEvent(.shareSnapshotClicked)

        guard let shareText = buildUsageShareSnapshotText() else {
            debugLog("shareUsageSnapshotClicked: no provider results available")
            showAlert(
                title: L("No Usage Data Yet"),
                message: L("Refresh usage data first, then try sharing again.")
            )
            return
        }

        copyToClipboard(shareText)
        debugLog("shareUsageSnapshotClicked: snapshot copied to clipboard")

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L("Usage Snapshot Copied")
        alert.informativeText = L("Your usage summary is in the clipboard. Open X to share it now.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Open X"))
        alert.addButton(withTitle: L("Close"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openXShareIntent(with: shareText)
            trackGrowthEvent(.shareSnapshotXOpened)
            debugLog("shareUsageSnapshotClicked: x intent opened")
        } else {
            debugLog("shareUsageSnapshotClicked: closed without opening x intent")
        }
    }
    
    @objc func viewErrorDetailsClicked() {
        logger.info("[Keyboard] Command-E View Error Details triggered")
        debugLog("viewErrorDetailsClicked: Command-E shortcut activated")
        showErrorDetailsAlert()
    }

    @objc func confirmResetOrphanedSubscriptions(_ sender: NSMenuItem) {
        // Capture current orphaned state to avoid races while the modal alert is open
        // (auto-refresh can rebuild the menu and mutate orphanedSubscriptionKeys).
        let keysToReset = orphanedSubscriptionKeys
        let totalToReset = orphanedSubscriptionTotal

        guard !keysToReset.isEmpty else {
            debugLog("confirmResetOrphanedSubscriptions: no orphaned subscriptions to reset")
            return
        }

        let orphanedCount = keysToReset.count
        let formattedTotal = String(format: "%.2f", totalToReset)
        let sanitizedKeys = keysToReset.map { sanitizedSubscriptionKey($0) }.joined(separator: ", ")
        debugLog("confirmResetOrphanedSubscriptions: \(orphanedCount) key(s) pending, total=$\(formattedTotal), keys=[\(sanitizedKeys)]")

        let countText: String
        if orphanedCount == 1 {
            countText = L("One saved subscription setting is no longer connected to a detected account or provider.")
        } else {
            countText = String(
                format: L("%d saved subscription settings are no longer connected to a detected account or provider."),
                orphanedCount
            )
        }
        let detailText = [
            countText,
            L("This usually happens after signing out, changing accounts, or removing a provider."),
            String(format: L("Amount to clear: $%@."), formattedTotal)
        ].joined(separator: "\n\n")
        debugLog("confirmResetOrphanedSubscriptions: showing localized clear confirmation")

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L("Clear outdated subscription settings?")
        alert.informativeText = detailText
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Clear"))
        alert.addButton(withTitle: L("Cancel"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            resetOrphanedSubscriptions(keys: keysToReset, expectedTotal: totalToReset)
        } else {
            debugLog("confirmResetOrphanedSubscriptions: reset cancelled")
        }
    }

    private func resetOrphanedSubscriptions(keys: [String], expectedTotal: Double) {
        guard !keys.isEmpty else {
            debugLog("resetOrphanedSubscriptions: no keys provided, skipping")
            return
        }

        let orphanedCount = keys.count
        let formattedTotal = String(format: "%.2f", expectedTotal)
        let sanitizedKeys = keys.map { sanitizedSubscriptionKey($0) }.joined(separator: ", ")
        debugLog("resetOrphanedSubscriptions: resetting \(orphanedCount) key(s), total=$\(formattedTotal), keys=[\(sanitizedKeys)]")
        logger.info("Resetting orphaned subscription entries: count=\(orphanedCount), total=$\(formattedTotal)")

        SubscriptionSettingsManager.shared.removePlans(forKeys: keys)

        let remainingKeys = Set(keys).intersection(SubscriptionSettingsManager.shared.getAllSubscriptionKeys())
        if remainingKeys.isEmpty {
            debugLog("resetOrphanedSubscriptions: removed all keys successfully")
        } else {
            let sanitizedRemaining = remainingKeys.map { sanitizedSubscriptionKey($0) }.sorted().joined(separator: ", ")
            debugLog("resetOrphanedSubscriptions: failed to remove \(remainingKeys.count) key(s): [\(sanitizedRemaining)]")
        }

        orphanedSubscriptionKeys = []
        orphanedSubscriptionTotal = 0
        updateMultiProviderMenu()
    }
    
    private func showErrorDetailsAlert() {
        guard !lastProviderErrors.isEmpty else {
            debugLog("showErrorDetailsAlert: no errors to show")
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        var errorLogText = "Provider Errors:\n"
        errorLogText += String(repeating: "─", count: 40) + "\n\n"
        
        for (identifier, errorMessage) in lastProviderErrors.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            errorLogText += "[\(identifier.displayName)]\n"
            errorLogText += "  \(errorMessage)\n\n"
        }
        
        errorLogText += String(repeating: "─", count: 40) + "\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        errorLogText += "Time: \(dateFormatter.string(from: Date()))\n"
        errorLogText += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\n"
        errorLogText += "\n"
        errorLogText += TokenManager.shared.getDebugEnvironmentInfo()
        errorLogText += "\n"
        errorLogText = PrivacyRedactor.redactSensitiveContentIfNeeded(errorLogText)
        
        let alert = NSAlert()
        alert.messageText = L("Provider Errors Detected")
        alert.informativeText = L("Some providers failed to fetch data. You can copy the error log and report this issue on GitHub.")
        alert.alertStyle = .warning
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 450, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = errorLogText
        textView.autoresizingMask = [.width, .height]
        
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        
        alert.addButton(withTitle: L("Copy & Report on GitHub"))
        alert.addButton(withTitle: L("Copy Log Only"))
        alert.addButton(withTitle: L("Close"))
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            debugLog("showErrorDetailsAlert: user chose Copy & Report on GitHub")
            copyToClipboard(errorLogText)
            openGitHubNewIssue()
            
        case .alertSecondButtonReturn:
            debugLog("showErrorDetailsAlert: user chose Copy Log Only")
            copyToClipboard(errorLogText)
            showCopiedConfirmation()
            
        default:
            debugLog("showErrorDetailsAlert: user closed")
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Text copied to clipboard")
    }

    private func buildUsageShareSnapshotText() -> String? {
        guard !providerResults.isEmpty else {
            return nil
        }

        let totalTracked = calculateTotalWithSubscriptions(
            providerResults: providerResults,
            copilotUsage: currentUsage
        )
        let payAsYouGoTotal = calculatePayAsYouGoTotal(
            providerResults: providerResults,
            copilotUsage: currentUsage
        )
        let subscriptionTotal = calculateVisibleSubscriptionTotal()

        var lines = [
            "My UsageBar usage snapshot",
            String(format: "- Total tracked this month: $%.2f", totalTracked),
            String(format: "- Pay-as-you-go spend: $%.2f", payAsYouGoTotal),
            String(format: "- Quota subscriptions: $%.2f/m", subscriptionTotal)
        ]

        if let topPayAsYouGo = topPayAsYouGoShareLine() {
            lines.append("- \(topPayAsYouGo)")
        }

        if let topQuota = topQuotaShareLine() {
            lines.append("- \(topQuota)")
        }

        lines.append("")
        lines.append("Track your AI provider usage in one menu bar app:")
        lines.append("https://github.com/SHLE1/usage-bar")

        return lines.joined(separator: "\n")
    }

    private func topPayAsYouGoShareLine() -> String? {
        var candidates: [(name: String, cost: Double)] = []

        let payAsYouGoOrder: [ProviderIdentifier] = [.openRouter, .openCode]
        for identifier in payAsYouGoOrder where isProviderEnabled(identifier) {
            guard let result = providerResults[identifier] else { continue }
            guard case .payAsYouGo(_, let cost, _) = result.usage else { continue }
            guard let cost, cost > 0 else { continue }
            candidates.append((name: identifier.displayName, cost: cost))
        }

        if isCopilotAddOnEnabled,
           isProviderEnabled(.copilot),
           let copilotOverageCost = providerResults[.copilot]?.details?.copilotOverageCost,
           copilotOverageCost > 0 {
            candidates.append((name: "GitHub Copilot Add-on", cost: copilotOverageCost))
        }

        guard let top = candidates.max(by: { $0.cost < $1.cost }) else {
            return nil
        }

        return String(format: "Top spend: %@ at $%.2f", top.name, top.cost)
    }

    private func topQuotaShareLine() -> String? {
        let candidates = providerResults.compactMap { identifier, result -> (name: String, usagePercent: Double)? in
            guard isProviderEnabled(identifier) else { return nil }
            guard case .quotaBased = result.usage else { return nil }
            return (name: identifier.displayName, usagePercent: max(0, result.usage.usagePercentage))
        }

        guard let top = candidates.max(by: { $0.usagePercent < $1.usagePercent }) else {
            return nil
        }

        return String(format: "Highest quota usage: %@ at %.0f%% used", top.name, top.usagePercent)
    }

    private func openXShareIntent(with text: String) {
        var components = URLComponents(string: "https://x.com/intent/post")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]

        guard let url = components?.url else {
            debugLog("openXShareIntent: failed to build URL")
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func trackGrowthEvent(_ event: GrowthEvent) {
        let keyPrefix = "growth.\(event.rawValue)"
        let countKey = "\(keyPrefix).count"
        let timestampKey = "\(keyPrefix).lastTimestamp"
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
        logger.info("Growth event recorded: \(event.rawValue, privacy: .public), count: \(count)")
        debugLog("growthEvent: \(event.rawValue), count=\(count)")
    }
    
    private func showCopiedConfirmation() {
        let confirmAlert = NSAlert()
        confirmAlert.messageText = L("Copied!")
        confirmAlert.informativeText = L("Error log has been copied to clipboard.")
        confirmAlert.alertStyle = .informational
        confirmAlert.addButton(withTitle: L("OK"))
        confirmAlert.runModal()
    }
    
    private func openGitHubNewIssue() {
        let title = "Bug Report: Provider fetch errors"
        let body = """
        **Describe the issue:**
        Describe what you were doing when the error occurred.
        
        **Error Log:**
        ```
        Paste the copied error log here, or remove this section if it contains sensitive information.
        ```
        
        **Environment:**
        - App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        - macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
        
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "https://github.com/SHLE1/usage-bar/issues/new?title=\(encodedTitle)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Prompts user to star GitHub repo once on first launch.
    private func checkAndPromptGitHubStar() {
        let dismissedKey = "githubStarPromptDismissed"
        guard !UserDefaults.standard.bool(forKey: dismissedKey) else {
            debugLog("GitHub star prompt: skipped (already dismissed)")
            return
        }

        debugLog("GitHub star prompt: showing alert")
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L("Support UsageBar?")
        alert.informativeText = L("If you find this app useful, would you like to star it on GitHub? It helps others discover this project.\n\nBased on the original opgginc/opencode-bar project.")
        alert.addButton(withTitle: L("Open GitHub"))
        alert.addButton(withTitle: L("No Thanks"))
        alert.alertStyle = .informational

        let response = alert.runModal()
        UserDefaults.standard.set(true, forKey: dismissedKey)

        if response == .alertFirstButtonReturn {
            debugLog("GitHub star prompt: opening GitHub page")
            if let url = URL(string: "https://github.com/SHLE1/usage-bar") {
                NSWorkspace.shared.open(url)
            }
        } else {
            debugLog("GitHub star prompt: user declined")
        }
    }

    @objc func quitClicked() {
        logger.info("[Keyboard] Command-Q Quit triggered")
        debugLog("quitClicked: Command-Q shortcut activated")
        NSApp.terminate(nil)
    }

    @objc func launchAtLoginClicked() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            logger.error("Launch at login toggle failed: \(error.localizedDescription)")
        }
        updateLaunchAtLoginState()
    }

    @objc func installCLIClicked() {
        logger.info("[Keyboard] Install CLI triggered")
        debugLog("installCLIClicked: Install CLI menu item activated")
        
        // Resolve CLI binary path via bundle URL (Contents/MacOS/usagebar-cli)
        let cliURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/usagebar-cli")
        let cliPath = cliURL.path
        
        guard FileManager.default.fileExists(atPath: cliPath) else {
            logger.error("CLI binary not found in app bundle at \(cliPath)")
            debugLog("CLI binary not found at expected path in app bundle")
            showAlert(title: L("CLI Not Found"), message: L("CLI binary not found in app bundle. Please reinstall the app."))
            return
        }
        
        debugLog("CLI binary found at: \(cliPath)")
        
        // Escape cliPath for safe inclusion in AppleScript string literal
        let escapedCliPath = cliPath.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Use AppleScript's 'quoted form of' to safely escape the path for the shell command and prevent command injection
        let script = """
        set cliPath to "\(escapedCliPath)"
        do shell script "mkdir -p /usr/local/bin && cp " & quoted form of cliPath & " /usr/local/bin/usagebar && chmod +x /usr/local/bin/usagebar" with administrator privileges
        """
        
        debugLog("Executing AppleScript for privileged installation")
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                logger.error("CLI installation failed: \(error.description)")
                debugLog("Installation failed: \(error.description)")
                showAlert(title: L("Installation Failed"), message: "Failed to install CLI: \(error.description)")
            } else {
                logger.info("CLI installed successfully to /usr/local/bin/usagebar")
                debugLog("CLI installed successfully")
                showAlert(title: L("Success"), message: L("CLI installed to /usr/local/bin/usagebar\n\nYou can now use 'usagebar' command in Terminal."))
                updateCLIInstallState()
            }
        } else {
            logger.error("Failed to create AppleScript object")
            debugLog("Failed to create AppleScript object")
            showAlert(title: L("Installation Failed"), message: L("Failed to create installation script."))
        }
    }

    func updateCLIInstallState() {
        let installed = FileManager.default.fileExists(atPath: "/usr/local/bin/usagebar")
        
        if installed {
            installCLIItem.title = L("CLI Installed (usagebar)")
            installCLIItem.state = .on
            installCLIItem.isEnabled = false
            debugLog("CLI is installed at /usr/local/bin/usagebar")
        } else {
            installCLIItem.title = L("Install CLI (usagebar)")
            installCLIItem.state = .off
            installCLIItem.isEnabled = true
            debugLog("CLI is not installed")
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("OK"))
        alert.alertStyle = .informational
        
        alert.runModal()
    }

    private func saveCache(usage: CopilotUsage) {
        if let data = try? JSONEncoder().encode(CachedUsage(usage: usage, timestamp: Date())) {
            UserDefaults.standard.set(data, forKey: "copilot.usage.cache")
        }
    }

    private func clearCaches() {
        UserDefaults.standard.removeObject(forKey: "copilot.history.cache")
    }

    private func saveHistoryCache(_ history: UsageHistory) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "copilot.history.cache")
        }
    }

    private func loadHistoryCache() -> UsageHistory? {
        guard let data = UserDefaults.standard.data(forKey: "copilot.history.cache") else { return nil }
        return try? JSONDecoder().decode(UsageHistory.self, from: data)
    }

    private func hasMonthChanged(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date) != calendar.component(.month, from: Date())
            || calendar.component(.year, from: date) != calendar.component(.year, from: Date())
    }

    func loadCachedHistoryOnStartup() {
        guard let cached = loadHistoryCache() else {
            logger.info("No cache - skipping history load")
            return
        }

        if hasMonthChanged(cached.fetchedAt) {
            logger.info("Month change detected - deleting cache")
            UserDefaults.standard.removeObject(forKey: "copilot.history.cache")
            return
        }

        self.usageHistory = cached
        self.lastHistoryFetchResult = .failedWithCache
        updateHistorySubmenu()
    }

    func getHistoryUIState() -> HistoryUIState {
        guard let history = usageHistory else {
            return HistoryUIState(history: nil, prediction: nil, isStale: false, hasNoData: true)
        }

        let stale = isHistoryStale(history)

        return HistoryUIState(
            history: history,
            prediction: nil,
            isStale: stale && lastHistoryFetchResult == .failedWithCache,
            hasNoData: false
        )
    }

    private func isHistoryStale(_ history: UsageHistory) -> Bool {
        let staleThreshold: TimeInterval = 30 * 60
        return Date().timeIntervalSince(history.fetchedAt) > staleThreshold
    }

    // MARK: - Predicted EOM Section (Aggregated Pay-as-you-go)

    func insertPredictedEOMSection(at index: Int) -> Int {
        var insertIndex = index

        // Collect daily cost data from all Pay-as-you-go providers
        var aggregatedDailyCosts: [Date: [ProviderIdentifier: Double]] = [:]

        // 1. Copilot Add-on history (only when add-on is enabled)
        if isCopilotAddOnEnabled, let history = usageHistory {
            for day in history.days {
                let dateKey = Calendar.current.startOfDay(for: day.date)
                if aggregatedDailyCosts[dateKey] == nil {
                    aggregatedDailyCosts[dateKey] = [:]
                }
                aggregatedDailyCosts[dateKey]?[.copilot] = day.billedAmount
            }
        }

        // 2. OpenCode history
        if let openCodeResult = providerResults[.openCode],
           let details = openCodeResult.details,
           let openCodeHistory = details.dailyHistory {
            for day in openCodeHistory {
                let dateKey = Calendar.current.startOfDay(for: day.date)
                if aggregatedDailyCosts[dateKey] == nil {
                    aggregatedDailyCosts[dateKey] = [:]
                }
                aggregatedDailyCosts[dateKey]?[.openCode] = day.billedAmount
            }
        }

        // 3. OpenRouter - only has current cost, no daily history
        // We'll include today's cost if available
        if let routerResult = providerResults[.openRouter],
           case .payAsYouGo = routerResult.usage,
           let dailyCost = routerResult.details?.dailyUsage {
            let today = Calendar.current.startOfDay(for: Date())
            if aggregatedDailyCosts[today] == nil {
                aggregatedDailyCosts[today] = [:]
            }
            aggregatedDailyCosts[today]?[.openRouter] = dailyCost
        }

        // If no data, skip this section
        guard !aggregatedDailyCosts.isEmpty else {
            return insertIndex
        }

        // Calculate predicted EOM
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let remainingDays = daysInMonth - currentDay

        // Get daily totals for prediction period
        let sortedDates = aggregatedDailyCosts.keys.sorted(by: >)
        let recentDays = Array(sortedDates.prefix(predictionPeriod.rawValue))

        var totalCostSoFar = 0.0
        var dailyTotals: [(date: Date, total: Double, breakdown: [ProviderIdentifier: Double])] = []

        for date in recentDays {
            if let providers = aggregatedDailyCosts[date] {
                let dayTotal = providers.values.reduce(0, +)
                totalCostSoFar += dayTotal
                dailyTotals.append((date: date, total: dayTotal, breakdown: providers))
            }
        }

        // Calculate weighted average daily cost
        let weights = predictionPeriod.weights
        var weightedSum = 0.0
        var weightTotal = 0.0

        for (index, dayData) in dailyTotals.enumerated() {
            let weight = index < weights.count ? weights[index] : 1.0
            weightedSum += dayData.total * weight
            weightTotal += weight
        }

        let avgDailyCost = weightTotal > 0 ? weightedSum / weightTotal : 0.0

        // Calculate current month total (sum all days in current month)
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        var currentMonthTotal = 0.0
        for (date, providers) in aggregatedDailyCosts {
            if date >= currentMonthStart {
                currentMonthTotal += providers.values.reduce(0, +)
            }
        }

        let predictedEOM = currentMonthTotal + (avgDailyCost * Double(remainingDays))

        // Create Predicted EOM menu item
        let eomItem = NSMenuItem(
            title: String(format: L("Predicted EOM: $%.0f"), predictedEOM),
            action: nil,
            keyEquivalent: ""
        )
        eomItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Predicted EOM")
        eomItem.tag = 999

        // Create submenu with daily breakdown
        let submenu = NSMenu()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d (EEE)"

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let todayStart = utcCalendar.startOfDay(for: today)

        // Sort dailyTotals by date descending
        let sortedDailyTotals = dailyTotals.sorted { $0.date > $1.date }

        for dayData in sortedDailyTotals.prefix(predictionPeriod.rawValue) {
            let dayStart = utcCalendar.startOfDay(for: dayData.date)
            let isToday = dayStart == todayStart
            let dateStr = dateFormatter.string(from: dayData.date)

            let costStr: String
            if dayData.total < 0.01 {
                costStr = L("Zero")
            } else {
                costStr = String(format: "$%.2f", dayData.total)
            }

            let label = isToday
                ? String(format: L("%@: %@ (Today)"), dateStr, costStr)
                : String(format: L("%@: %@"), dateStr, costStr)

            // Create day item with provider breakdown submenu
            let dayItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            dayItem.tag = 999

            // Only add submenu if there's more than one provider or any cost
            if !dayData.breakdown.isEmpty {
                let breakdownSubmenu = NSMenu()

                // Sort by provider display order
                let providerOrder: [ProviderIdentifier] = [.openCode, .openRouter, .copilot]
                for provider in providerOrder {
                    if let cost = dayData.breakdown[provider] {
                        let providerLabel: String
                        if cost < 0.01 {
                            providerLabel = String(format: L("%@: %@"), provider.displayName, L("Zero"))
                        } else {
                            providerLabel = String(format: L("%@: $%.2f"), provider.displayName, cost)
                        }
                        breakdownSubmenu.addItem(createDisabledMenuItem(
                            text: providerLabel,
                            icon: iconForProvider(provider)
                        ))
                    }
                }

                dayItem.submenu = breakdownSubmenu
            }

            submenu.addItem(dayItem)
        }

        // Add separator before settings
        submenu.addItem(NSMenuItem.separator())

        // Prediction Period submenu
        let periodItem = NSMenuItem(title: L("Prediction Period"), action: nil, keyEquivalent: "")
        periodItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("Prediction Period"))

        // Create a fresh submenu for prediction period to avoid deadlock
        let periodSubmenu = NSMenu()
        for period in PredictionPeriod.allCases {
            let item = NSMenuItem(title: period.title, action: #selector(predictionPeriodSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = period.rawValue
            item.state = (period.rawValue == predictionPeriod.rawValue) ? .on : .off
            periodSubmenu.addItem(item)
        }
        periodItem.submenu = periodSubmenu
        submenu.addItem(periodItem)

        submenu.addItem(NSMenuItem.separator())
        let authItem = NSMenuItem()
        authItem.view = createDisabledLabelView(
            text: String(format: L("Token From: %@"), PrivacyRedactor.display("~/.local/share/opencode/auth.json")),
            icon: NSImage(systemSymbolName: "key", accessibilityDescription: "Auth Source"),
            multiline: true
        )
        submenu.addItem(authItem)

        eomItem.submenu = submenu
        menu.insertItem(eomItem, at: insertIndex)
        insertIndex += 1

        return insertIndex
    }

    func updateHistorySubmenu() {
        debugLog("updateHistorySubmenu: started")
        let state = getHistoryUIState()
        debugLog("updateHistorySubmenu: getHistoryUIState completed")
        historySubmenu.removeAllItems()
        debugLog("updateHistorySubmenu: removeAllItems completed")

        if state.hasNoData {
            debugLog("updateHistorySubmenu: hasNoData=true, returning early")
            historySubmenu.addItem(createDisabledMenuItem(
                text: L("No data"),
                icon: NSImage(systemSymbolName: "tray", accessibilityDescription: L("No data"))
            ))
            return
        }
        debugLog("updateHistorySubmenu: hasNoData=false, continuing")

        if let prediction = state.prediction {
            debugLog("updateHistorySubmenu: prediction exists, processing")
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0

            debugLog("updateHistorySubmenu: creating monthlyText")
            let monthlyRequestCount = formatter.string(from: NSNumber(value: prediction.predictedMonthlyRequests)) ?? "0"
            let monthlyText = String(format: L("Predicted EOM: %@ requests"), monthlyRequestCount)
            debugLog("updateHistorySubmenu: creating monthlyItem")
            let monthlyItem = NSMenuItem()
            monthlyItem.view = createDisabledLabelView(
                text: monthlyText,
                icon: NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Predicted EOM"),
                font: NSFont.boldSystemFont(ofSize: 13)
            )
            debugLog("updateHistorySubmenu: adding monthlyItem to submenu")
            historySubmenu.addItem(monthlyItem)
            debugLog("updateHistorySubmenu: monthlyItem added")

            if isCopilotAddOnEnabled && prediction.predictedBilledAmount > 0 {
                let costText = String(format: L("Predicted Add-on: $%.2f"), prediction.predictedBilledAmount)
                let costItem = NSMenuItem()
                costItem.view = createDisabledLabelView(
                    text: costText,
                    icon: NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "Predicted Add-on"),
                    font: NSFont.boldSystemFont(ofSize: 13),
                    underline: true
                )
                historySubmenu.addItem(costItem)
            }

            if prediction.confidenceLevel == .low {
                historySubmenu.addItem(createDisabledMenuItem(
                    text: L("Low prediction accuracy"),
                    icon: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Low accuracy")
                ))
            } else if prediction.confidenceLevel == .medium {
                historySubmenu.addItem(createDisabledMenuItem(
                    text: L("Medium prediction accuracy"),
                    icon: NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Medium accuracy")
                ))
            }

            debugLog("updateHistorySubmenu: adding separator after prediction")
            historySubmenu.addItem(NSMenuItem.separator())
            debugLog("updateHistorySubmenu: separator added")
        } else {
            debugLog("updateHistorySubmenu: no prediction data")
        }

        if state.isStale {
            debugLog("updateHistorySubmenu: data is stale, adding stale item")
            historySubmenu.addItem(createDisabledMenuItem(
                text: L("Data is stale"),
                icon: NSImage(systemSymbolName: "clock.badge.exclamationmark", accessibilityDescription: L("Data is stale"))
            ))
            debugLog("updateHistorySubmenu: stale item added")
        }

        if let history = state.history {
            debugLog("updateHistorySubmenu: history exists, processing \(history.recentDays.count) days")

            var utcCalendar = Calendar(identifier: .gregorian)
            if let utc = TimeZone(identifier: "UTC") {
                utcCalendar.timeZone = utc
            }
            let today = utcCalendar.startOfDay(for: Date())

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 0

            for day in history.recentDays {
                let dayStart = utcCalendar.startOfDay(for: day.date)
                let isToday = dayStart == today
                let dateStr = SharedDateFormatters.monthDay.string(from: day.date)
                let reqStr = numberFormatter.string(from: NSNumber(value: day.totalRequests)) ?? "0"
                let label = isToday
                    ? String(format: L("%@ (Today): %@ req"), dateStr, reqStr)
                    : String(format: L("%@: %@ req"), dateStr, reqStr)

                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: label, monospaced: true)
                historySubmenu.addItem(item)
            }
            debugLog("updateHistorySubmenu: all history items added")
        } else {
            debugLog("updateHistorySubmenu: no history data")
        }

        debugLog("updateHistorySubmenu: adding final separator and prediction period menu")
        historySubmenu.addItem(NSMenuItem.separator())
        let predictionPeriodItem = NSMenuItem(title: L("Prediction Period"), action: nil, keyEquivalent: "")
        predictionPeriodItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("Prediction Period"))
        
        // Create a fresh submenu to avoid NSMenu parent conflict
        let freshPeriodSubmenu = NSMenu()
        for period in PredictionPeriod.allCases {
            let item = NSMenuItem(title: period.title, action: #selector(predictionPeriodSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = period.rawValue
            item.state = (period.rawValue == predictionPeriod.rawValue) ? .on : .off
            freshPeriodSubmenu.addItem(item)
        }
        predictionPeriodItem.submenu = freshPeriodSubmenu
        historySubmenu.addItem(predictionPeriodItem)
        debugLog("updateHistorySubmenu: completed successfully")
    }
}

// MARK: - Demo Mode (for marketing screenshots)
extension StatusBarController {
    /// Populates providerResults with rich fake data for marketing screenshots.
    /// Launch with --demo-mode to activate.
    func loadDemoData() {
        debugLog("[DemoMode] Loading demo data for marketing screenshots")
        
        let now = Date()
        let fiveHoursFromNow = now.addingTimeInterval(5 * 3600)
        let sevenDaysFromNow = now.addingTimeInterval(7 * 24 * 3600)
        let oneDayFromNow = now.addingTimeInterval(24 * 3600)
        let twoDaysFromNow = now.addingTimeInterval(2 * 24 * 3600)
        
        providerResults = [
            // --- Pay-as-you-go ---
            .openRouter: ProviderResult(
                usage: .payAsYouGo(utilization: 0, cost: 37.42, resetsAt: nil),
                details: DetailedUsage(
                    creditsRemaining: 62.58,
                    creditsTotal: 100.0,
                    authSource: "OpenCode"
                )
            ),
            .openCode: ProviderResult(
                usage: .payAsYouGo(utilization: 0, cost: 12.50, resetsAt: nil),
                details: DetailedUsage(
                    sessions: 47,
                    messages: 312,
                    avgCostPerDay: 0.42,
                    authSource: "opencode CLI"
                )
            ),
            
            // --- Quota-based ---
            .claude: ProviderResult(
                usage: .quotaBased(remaining: 23, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    fiveHourUsage: 52.0,
                    fiveHourReset: fiveHoursFromNow,
                    sevenDayUsage: 82.0,
                    sevenDayReset: sevenDaysFromNow,
                    sonnetUsage: 38.0,
                    sonnetReset: sevenDaysFromNow,
                    opusUsage: 95.0,
                    opusReset: sevenDaysFromNow,
                    extraUsageEnabled: false,
                    authSource: "OpenCode"
                )
            ),
            .codex: ProviderResult(
                usage: .quotaBased(remaining: 1, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    secondaryUsage: 45.0,
                    secondaryReset: sevenDaysFromNow,
                    primaryReset: fiveHoursFromNow,
                    creditsBalance: 180.0,
                    planType: "pro",
                    authSource: "Codex CLI"
                )
            ),
            .copilot: ProviderResult(
                usage: .quotaBased(remaining: 1200, entitlement: 1500, overagePermitted: true),
                details: DetailedUsage(
                    copilotOverageCost: 2.40,
                    copilotOverageRequests: 12,
                    copilotUsedRequests: 300,
                    copilotLimitRequests: 1500,
                    copilotQuotaResetDateUTC: oneDayFromNow
                )
            ),
            .kimi: ProviderResult(
                usage: .quotaBased(remaining: 74, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    fiveHourUsage: 26.0,
                    fiveHourReset: fiveHoursFromNow,
                    authSource: "OpenCode"
                )
            ),
            .minimaxCodingPlan: ProviderResult(
                usage: .quotaBased(remaining: 8, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    fiveHourUsage: 92.0,
                    fiveHourReset: fiveHoursFromNow,
                    sevenDayUsage: 68.0,
                    sevenDayReset: sevenDaysFromNow,
                    authSource: "OpenCode"
                )
            ),
            .zaiCodingPlan: ProviderResult(
                usage: .quotaBased(remaining: 1, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    tokenUsagePercent: 99.0,
                    tokenUsageReset: oneDayFromNow,
                    tokenUsageUsed: 990_000,
                    tokenUsageTotal: 1_000_000,
                    mcpUsagePercent: 45.0,
                    mcpUsageReset: oneDayFromNow,
                    mcpUsageUsed: 45,
                    mcpUsageTotal: 100,
                    modelUsageTokens: 500_000,
                    modelUsageCalls: 128,
                    toolNetworkSearchCount: 42,
                    toolWebReadCount: 15,
                    toolZreadCount: 8
                )
            ),
            .geminiCLI: ProviderResult(
                usage: .quotaBased(remaining: 85, entitlement: 100, overagePermitted: false),
                details: DetailedUsage(
                    authSource: "OpenCode",
                    geminiAccounts: [
                        GeminiAccountQuota(
                            accountIndex: 0,
                            email: "user@gmail.com",
                            accountId: "100663739661147150906",
                            remainingPercentage: 100.0,
                            modelBreakdown: [
                                "gemini-2.5-pro": 100.0,
                                "gemini-2.5-flash": 100.0
                            ],
                            authSource: "Gemini CLI",
                            earliestReset: sevenDaysFromNow,
                            modelResetTimes: [
                                "gemini-2.5-pro": sevenDaysFromNow,
                                "gemini-2.5-flash": sevenDaysFromNow
                            ]
                        ),
                        GeminiAccountQuota(
                            accountIndex: 1,
                            email: "work@company.com",
                            accountId: "109876543210987654321",
                            remainingPercentage: 70.0,
                            modelBreakdown: [
                                "gemini-2.5-pro": 70.0,
                                "gemini-2.5-flash": 85.0
                            ],
                            authSource: "Antigravity",
                            earliestReset: twoDaysFromNow,
                            modelResetTimes: [
                                "gemini-2.5-pro": twoDaysFromNow,
                                "gemini-2.5-flash": twoDaysFromNow
                            ]
                        )
                    ]
                )
            )
        ]
        
        // Clear any loading states
        loadingProviders.removeAll()
        lastProviderErrors.removeAll()
        
        debugLog("[DemoMode] Demo data loaded: \(providerResults.count) providers")
        
        // Rebuild the entire menu with demo data
        updateMultiProviderMenu()
        updateStatusBarText()
        
        debugLog("[DemoMode] Menu rebuilt with demo data")
    }
}
