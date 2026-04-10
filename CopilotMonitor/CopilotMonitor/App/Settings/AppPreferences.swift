import Foundation
import Combine
import ServiceManagement

/// Lightweight ObservableObject bridge over UserDefaults.
/// Both SwiftUI Settings views and StatusBarController read/write through this singleton
/// so that changes propagate immediately.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    // MARK: - Notification names (StatusBarController listens for these)

    static let refreshIntervalDidChange = Notification.Name("AppPreferences.refreshIntervalDidChange")
    static let predictionPeriodDidChange = Notification.Name("AppPreferences.predictionPeriodDidChange")
    static let displayModeDidChange = Notification.Name("AppPreferences.displayModeDidChange")
    static let enabledProvidersDidChange = Notification.Name("AppPreferences.enabledProvidersDidChange")
    static let criticalBadgeDidChange = Notification.Name("AppPreferences.criticalBadgeDidChange")
    static let showProviderIconDidChange = Notification.Name("AppPreferences.showProviderIconDidChange")
    static let multiProviderProvidersDidChange = Notification.Name("AppPreferences.multiProviderProvidersDidChange")
    static let subscriptionDidChange = Notification.Name("AppPreferences.subscriptionDidChange")
    static let copilotAddOnDidChange = Notification.Name("AppPreferences.copilotAddOnDidChange")

    private let defaults = UserDefaults.standard

    // MARK: - General

    @Published var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: "refreshInterval")
            NotificationCenter.default.post(name: Self.refreshIntervalDidChange, object: nil)
        }
    }

    @Published var predictionPeriod: PredictionPeriod {
        didSet {
            defaults.set(predictionPeriod.rawValue, forKey: "predictionPeriod")
            NotificationCenter.default.post(name: Self.predictionPeriodDidChange, object: nil)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Revert on failure
                _launchAtLogin = Published(wrappedValue: service.status == .enabled)
            }
        }
    }

    // MARK: - Status Bar

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(menuBarDisplayMode.rawValue, forKey: StatusBarDisplayPreferences.modeKey)
            NotificationCenter.default.post(name: Self.displayModeDidChange, object: nil)
        }
    }

    @Published var onlyShowMode: OnlyShowMode {
        didSet {
            defaults.set(onlyShowMode.rawValue, forKey: StatusBarDisplayPreferences.onlyShowModeKey)
            NotificationCenter.default.post(name: Self.displayModeDidChange, object: nil)
        }
    }

    @Published var pinnedProvider: ProviderIdentifier? {
        didSet {
            defaults.set(pinnedProvider?.rawValue, forKey: StatusBarDisplayPreferences.providerKey)
            NotificationCenter.default.post(name: Self.displayModeDidChange, object: nil)
        }
    }

    @Published var criticalBadge: Bool {
        didSet {
            defaults.set(criticalBadge, forKey: StatusBarDisplayPreferences.criticalBadgeKey)
            NotificationCenter.default.post(name: Self.criticalBadgeDidChange, object: nil)
        }
    }

    @Published var showProviderIcon: Bool {
        didSet {
            defaults.set(showProviderIcon, forKey: StatusBarDisplayPreferences.showProviderNameKey)
            NotificationCenter.default.post(name: Self.showProviderIconDidChange, object: nil)
        }
    }

    @Published var multiProviderProviders: Set<ProviderIdentifier> {
        didSet {
            let rawValues = multiProviderProviders.map { $0.rawValue }
            defaults.set(rawValues, forKey: StatusBarDisplayPreferences.multiProviderProvidersKey)
            NotificationCenter.default.post(name: Self.multiProviderProvidersDidChange, object: nil)
        }
    }

    // MARK: - Copilot Add-on

    @Published var copilotAddOnEnabled: Bool {
        didSet {
            defaults.set(copilotAddOnEnabled, forKey: "provider.copilot_add_on.enabled")
            NotificationCenter.default.post(name: Self.copilotAddOnDidChange, object: nil)
        }
    }

    // MARK: - Provider Enabled/Disabled

    func isProviderEnabled(_ identifier: ProviderIdentifier) -> Bool {
        let key = "provider.\(identifier.rawValue).enabled"
        if defaults.object(forKey: key) == nil {
            return true
        }
        return defaults.bool(forKey: key)
    }

    func setProviderEnabled(_ identifier: ProviderIdentifier, enabled: Bool) {
        let key = "provider.\(identifier.rawValue).enabled"
        defaults.set(enabled, forKey: key)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.enabledProvidersDidChange, object: nil)
    }

    // MARK: - Init (read current values from UserDefaults)

    private init() {
        let rawRefresh = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: rawRefresh) ?? .defaultInterval

        let rawPrediction = UserDefaults.standard.integer(forKey: "predictionPeriod")
        self.predictionPeriod = PredictionPeriod(rawValue: rawPrediction) ?? .defaultPeriod

        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        // Note: getter in StatusBarController is hardcoded to .multiProvider.
        // We read the actual stored value so the Settings UI reflects reality.
        let rawMode = UserDefaults.standard.integer(forKey: StatusBarDisplayPreferences.modeKey)
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: rawMode) ?? .defaultMode

        if let rawOnly = UserDefaults.standard.object(forKey: StatusBarDisplayPreferences.onlyShowModeKey) as? Int {
            self.onlyShowMode = OnlyShowMode(rawValue: rawOnly) ?? .defaultMode
        } else {
            self.onlyShowMode = .defaultMode
        }

        if let rawProvider = UserDefaults.standard.string(forKey: StatusBarDisplayPreferences.providerKey) {
            self.pinnedProvider = ProviderIdentifier(rawValue: rawProvider)
        } else {
            self.pinnedProvider = nil
        }

        if UserDefaults.standard.object(forKey: StatusBarDisplayPreferences.criticalBadgeKey) != nil {
            self.criticalBadge = UserDefaults.standard.bool(forKey: StatusBarDisplayPreferences.criticalBadgeKey)
        } else {
            self.criticalBadge = true // default
        }

        if UserDefaults.standard.object(forKey: StatusBarDisplayPreferences.showProviderNameKey) != nil {
            self.showProviderIcon = UserDefaults.standard.bool(forKey: StatusBarDisplayPreferences.showProviderNameKey)
        } else {
            self.showProviderIcon = false // default
        }

        if let rawProviders = UserDefaults.standard.array(forKey: StatusBarDisplayPreferences.multiProviderProvidersKey) as? [String] {
            self.multiProviderProviders = Set(rawProviders.compactMap { ProviderIdentifier(rawValue: $0) })
        } else {
            self.multiProviderProviders = Set(ProviderIdentifier.allCases)
        }

        if UserDefaults.standard.object(forKey: "provider.copilot_add_on.enabled") != nil {
            self.copilotAddOnEnabled = UserDefaults.standard.bool(forKey: "provider.copilot_add_on.enabled")
        } else {
            self.copilotAddOnEnabled = true // default
        }
    }

    /// Refresh launch-at-login state from the system (call after external changes)
    func refreshLaunchAtLoginState() {
        let current = SMAppService.mainApp.status == .enabled
        if launchAtLogin != current {
            launchAtLogin = current
        }
    }
}
