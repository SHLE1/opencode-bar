import AppKit
import os.log

private let statusBarMenuLogger = Logger(subsystem: "com.opencodeproviders", category: "StatusBarController")

extension StatusBarController {
    private enum ErrorMenuStatus {
        case rateLimited
        case noCredentials
        case noSubscription
        case error

        var title: String {
            switch self {
            case .rateLimited:
                return L("Rate limited")
            case .noCredentials:
                return L("No Credentials")
            case .noSubscription:
                return L("No Subscription")
            case .error:
                return L("Error")
            }
        }

        var shouldDeferToBottom: Bool {
            switch self {
            case .rateLimited, .error:
                return false
            case .noCredentials, .noSubscription:
                return true
            }
        }

        var shouldDisplayInList: Bool {
            switch self {
            case .noCredentials:
                return false
            case .rateLimited, .noSubscription, .error:
                return true
            }
        }

        var shouldDisableListItem: Bool {
            switch self {
            case .rateLimited:
                return true
            case .noCredentials, .noSubscription:
                return false
            case .error:
                return false
            }
        }
    }

    func updateMultiProviderMenu() {
        debugLog("updateMultiProviderMenu: started")
        if isMainMenuTracking {
            hasDeferredMenuRebuild = true
            hasDeferredStatusBarRefresh = true
            debugLog("updateMultiProviderMenu: deferred while menu is open")
            return
        }
        hasDeferredMenuRebuild = false

        guard let separatorIndex = menu.items.firstIndex(where: { $0.isSeparatorItem }) else {
            debugLog("updateMultiProviderMenu: no separator found, returning")
            return
        }
        debugLog("updateMultiProviderMenu: separatorIndex=\(separatorIndex)")

        var itemsToRemove: [NSMenuItem] = []
        let startIndex = separatorIndex + 1
        if startIndex < menu.items.count {
            for i in startIndex..<menu.items.count where menu.items[i].tag == 999 {
                itemsToRemove.append(menu.items[i])
            }
        }
        debugLog("updateMultiProviderMenu: removing \(itemsToRemove.count) old items")
        itemsToRemove.forEach { menu.removeItem($0) }

        debugLog("updateMultiProviderMenu: providerResults.count=\(providerResults.count)")
        if !providerResults.isEmpty {
            let providerNames = providerResults.keys.map { $0.rawValue }.joined(separator: ", ")
            debugLog("updateMultiProviderMenu: providers=[\(providerNames)]")
        }

        guard !providerResults.isEmpty || !lastProviderErrors.isEmpty || !loadingProviders.isEmpty else {
            debugLog("updateMultiProviderMenu: no data, returning")
            updateStatusBarDisplayMenuState()
            updateStatusBarText()
            return
        }

        var insertIndex = separatorIndex + 1
        let payAsYouGoTotal = calculatePayAsYouGoTotal(providerResults: providerResults, copilotUsage: currentUsage)
        let subscriptionTotal = SubscriptionSettingsManager.shared.getTotalMonthlySubscriptionCost()

        let payAsYouGoSectionStartIndex = insertIndex
        let separator1 = NSMenuItem.separator()
        separator1.tag = 999
        menu.insertItem(separator1, at: insertIndex)
        insertIndex += 1

        let payAsYouGoHeader = createSectionHeaderItem(title: String(format: L("Pay-as-you-go: $%.2f"), payAsYouGoTotal))
        payAsYouGoHeader.tag = 999
        menu.insertItem(payAsYouGoHeader, at: insertIndex)
        insertIndex += 1

        var hasPayAsYouGo = false
        insertOrderedPayAsYouGoItems(at: &insertIndex, hasPayAsYouGo: &hasPayAsYouGo)

        if hasPayAsYouGo {
            insertIndex = insertPredictedEOMSection(at: insertIndex)
        } else {
            debugLog("updateMultiProviderMenu: hiding pay-as-you-go section because no visible items were generated")
            while insertIndex > payAsYouGoSectionStartIndex {
                insertIndex -= 1
                menu.removeItem(at: insertIndex)
            }
        }

        let quotaSectionStartIndex = insertIndex
        let separator2 = NSMenuItem.separator()
        separator2.tag = 999
        menu.insertItem(separator2, at: insertIndex)
        insertIndex += 1

        let quotaTitle = subscriptionTotal > 0
            ? String(format: L("Quota Status: $%.0f/m"), subscriptionTotal)
            : L("Quota Status")
        let quotaHeader = createSectionHeaderItem(title: quotaTitle)
        quotaHeader.tag = 999
        menu.insertItem(quotaHeader, at: insertIndex)
        insertIndex += 1

        var hasQuota = false
        insertOrderedQuotaItems(at: &insertIndex, hasQuota: &hasQuota)

        if !hasQuota {
            debugLog("updateMultiProviderMenu: hiding quota section because no visible items were generated")
            while insertIndex > quotaSectionStartIndex {
                insertIndex -= 1
                menu.removeItem(at: insertIndex)
            }
        }

        let orphaned = calculateOrphanedSubscriptions(providerResults: providerResults)
        orphanedSubscriptionKeys = orphaned.keys
        orphanedSubscriptionTotal = orphaned.total
        if orphaned.total > 0 {
            let title = String(format: L("Outdated subscriptions ($%.2f)"), orphaned.total)
            let orphanedItem = NSMenuItem(title: title, action: #selector(confirmResetOrphanedSubscriptions(_:)), keyEquivalent: "")
            orphanedItem.target = self
            orphanedItem.attributedTitle = italicMenuTitle(title)
            orphanedItem.image = orphanedIcon()
            orphanedItem.tag = 999
            menu.insertItem(orphanedItem, at: insertIndex)
            insertIndex += 1
        }

        let hasDynamicMenuContent = insertIndex > separatorIndex + 1
        if hasDynamicMenuContent {
            let separator3 = NSMenuItem.separator()
            separator3.tag = 999
            menu.insertItem(separator3, at: insertIndex)
        } else {
            debugLog("updateMultiProviderMenu: skipping trailing dynamic separator because all dynamic sections are hidden")
        }

        let totalCost = calculateTotalWithSubscriptions(providerResults: providerResults, copilotUsage: currentUsage)
        updateStatusBarDisplayMenuState()
        updateStatusBarText()
        debugLog("updateMultiProviderMenu: completed successfully, totalCost=$\(totalCost)")
        logMenuStructure()
    }

    func logMenuStructure() {
        let total = menu.items.count
        let separators = menu.items.filter { $0.isSeparatorItem }.count
        let withAction = menu.items.filter { !$0.isSeparatorItem && $0.action != nil }.count
        let withSubmenu = menu.items.filter { $0.hasSubmenu }.count

        statusBarMenuLogger.info("[Menu] Items: \(total) (sep:\(separators), actions:\(withAction), submenus:\(withSubmenu))")

        var output = "\n========== MENU STRUCTURE ==========\n"
        for (index, item) in menu.items.enumerated() {
            output += logMenuItem(item, depth: 0, index: index)
        }
        output += "====================================\n"
        debugLog(output)
    }

    private func logMenuItem(_ item: NSMenuItem, depth: Int, index: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var line = ""

        if item.isSeparatorItem {
            line = "\(indent)[\(index)] ─────────────\n"
        } else if let view = item.view {
            let viewType = String(describing: type(of: view))
            if let label = view.subviews.compactMap({ $0 as? NSTextField }).first {
                line = "\(indent)[\(index)] [VIEW:\(viewType)] \(label.stringValue)\n"
            } else {
                line = "\(indent)[\(index)] [VIEW:\(viewType)]\n"
            }
        } else {
            line = "\(indent)[\(index)] \(item.title)\n"
        }

        if let submenu = item.submenu {
            for (subIndex, subItem) in submenu.items.enumerated() {
                line += logMenuItem(subItem, depth: depth + 1, index: subIndex)
            }
        }

        return line
    }

    func sanitizedSubscriptionKey(_ key: String) -> String {
        let parts = key.split(separator: ".")
        guard parts.count >= 3 else { return key }
        let prefix = parts.prefix(2).joined(separator: ".")
        return "\(prefix).<redacted>"
    }

    private func orphanedIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: L("Outdated subscriptions"))
        image?.size = NSSize(width: MenuDesignToken.Dimension.iconSize, height: MenuDesignToken.Dimension.iconSize)
        return image
    }

    private func italicMenuTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: NSFontManager.shared.convert(MenuDesignToken.Typography.defaultFont, toHaveTrait: .italicFontMask)]
        )
    }

    private func providerIdentifier(for subscriptionKey: String) -> ProviderIdentifier? {
        let prefix = subscriptionKey
            .replacingOccurrences(of: "subscription_v2.", with: "")
            .split(separator: ".")
            .first
            .map(String.init)

        guard let prefix else { return nil }
        return ProviderIdentifier.allCases.first { $0.rawValue == prefix }
    }

    private func collectVisibleSubscriptionKeys(providerResults: [ProviderIdentifier: ProviderResult]) -> Set<String> {
        var keys = Set<String>()

        for (identifier, result) in providerResults {
            guard isProviderEnabled(identifier) else { continue }

            if identifier == .geminiCLI,
               let details = result.details,
               let geminiAccounts = details.geminiAccounts,
               !geminiAccounts.isEmpty {
                for account in geminiAccounts {
                    let trimmedEmail = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let subscriptionAccountId: String? =
                        !trimmedEmail.isEmpty ? trimmedEmail :
                        ((account.accountId?.isEmpty == false) ? account.accountId : nil)
                    let key = SubscriptionSettingsManager.shared.subscriptionKey(for: .geminiCLI, accountId: subscriptionAccountId)
                    keys.insert(key)
                }
                continue
            }

            if let accounts = result.accounts, !accounts.isEmpty {
                for account in accounts {
                    if let subId = account.subscriptionId, !subId.isEmpty {
                        keys.insert(SubscriptionSettingsManager.shared.subscriptionKey(for: identifier, accountId: subId))
                    } else {
                        keys.insert(SubscriptionSettingsManager.shared.subscriptionKey(for: identifier))
                    }
                }
            } else {
                keys.insert(SubscriptionSettingsManager.shared.subscriptionKey(for: identifier))
            }
        }

        return keys
    }

    private func calculateOrphanedSubscriptions(providerResults: [ProviderIdentifier: ProviderResult]) -> (keys: [String], total: Double) {
        let visibleKeys = collectVisibleSubscriptionKeys(providerResults: providerResults)
        let allKeys = SubscriptionSettingsManager.shared.getAllSubscriptionKeys()

        var orphaned: [String] = []
        var total = 0.0

        for key in allKeys {
            if visibleKeys.contains(key) {
                continue
            }

            if let provider = providerIdentifier(for: key) {
                if loadingProviders.contains(provider) || !isProviderEnabled(provider) || !providerResults.keys.contains(provider) {
                    continue
                }
            } else {
                let plan = SubscriptionSettingsManager.shared.getPlan(forKey: key)
                if plan.cost <= 0 {
                    continue
                }
                orphaned.append(key)
                total += plan.cost
                continue
            }

            let plan = SubscriptionSettingsManager.shared.getPlan(forKey: key)
            if plan.cost <= 0 {
                continue
            }

            orphaned.append(key)
            total += plan.cost
        }

        if orphaned.isEmpty {
            debugLog("Orphaned subscriptions: none")
        } else {
            let formattedTotal = String(format: "%.2f", total)
            let sanitizedKeys = orphaned.map { sanitizedSubscriptionKey($0) }.joined(separator: ", ")
            debugLog("Orphaned subscriptions detected: \(orphaned.count) key(s), total=$\(formattedTotal), keys=[\(sanitizedKeys)]")
        }

        return (orphaned, total)
    }

    private func insertOrderedPayAsYouGoItems(at insertIndex: inout Int, hasPayAsYouGo: inout Bool) {
        let payAsYouGoOrder = AppPreferences.shared.payAsYouGoSettingsItemOrder(
            providers: AppPreferences.statusBarPayAsYouGoProviders
        )
        debugLog("updateMultiProviderMenu: pay-as-you-go order=[\(payAsYouGoOrder.joined(separator: ", "))]")

        for storageKey in payAsYouGoOrder {
            if storageKey == AppPreferences.copilotAddOnStorageKey {
                insertCopilotAddOnMenuItem(at: &insertIndex, hasPayAsYouGo: &hasPayAsYouGo)
                continue
            }

            guard let identifier = ProviderIdentifier(rawValue: storageKey) else { continue }
            insertPayAsYouGoProviderMenuItem(identifier, at: &insertIndex, hasPayAsYouGo: &hasPayAsYouGo)
        }
    }

    private func insertPayAsYouGoProviderMenuItem(
        _ identifier: ProviderIdentifier,
        at insertIndex: inout Int,
        hasPayAsYouGo: inout Bool
    ) {
        guard isProviderEnabled(identifier) else { return }

        let result = providerResults[identifier]
        let errorMessage = lastProviderErrors[identifier]

        if let errorMessage, shouldDisplayErrorStateEvenWithResult(errorMessage) {
            hasPayAsYouGo = true
            let item = createErrorMenuItem(identifier: identifier, errorMessage: errorMessage)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: identifier, result: result, errorMessage: errorMessage)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if let result,
           case .payAsYouGo(_, let cost, _) = result.usage {
            hasPayAsYouGo = true
            let costValue = cost ?? 0.0
            let item = NSMenuItem(
                title: String(format: L("%@ ($%.2f)"), identifier.displayName, costValue),
                action: nil,
                keyEquivalent: ""
            )
            item.image = iconForProvider(identifier)
            item.tag = 999

            if let details = result.details, details.hasAnyValue {
                item.submenu = createDetailSubmenu(details, identifier: identifier)
            }

            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if let errorMessage {
            guard shouldDisplayErrorMenuItem(errorMessage) else {
                debugLog("updateMultiProviderMenu: hiding \(identifier.displayName) pay-as-you-go row because credentials are unavailable")
                return
            }
            hasPayAsYouGo = true
            let item = createErrorMenuItem(identifier: identifier, errorMessage: errorMessage)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: identifier, result: nil, errorMessage: errorMessage)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if loadingProviders.contains(identifier) {
            hasPayAsYouGo = true
            let item = NSMenuItem(title: String(format: L("%@ (Loading...)"), identifier.displayName), action: nil, keyEquivalent: "")
            item.image = iconForProvider(identifier)
            item.isEnabled = false
            item.tag = 999
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }
    }

    private func insertCopilotAddOnMenuItem(at insertIndex: inout Int, hasPayAsYouGo: inout Bool) {
        guard isProviderEnabled(.copilot), isCopilotAddOnEnabled else { return }

        if let copilotResult = providerResults[.copilot],
           let details = copilotResult.details,
           let overageCost = details.copilotOverageCost {
            hasPayAsYouGo = true
            let addOnItem = NSMenuItem(
                title: String(format: L("Copilot Add-on ($%.2f)"), overageCost),
                action: nil,
                keyEquivalent: ""
            )
            addOnItem.image = iconForProvider(.copilot)
            addOnItem.tag = 999

            let submenu = NSMenu()
            let overageRequests = details.copilotOverageRequests ?? 0
            submenu.addItem(createDisabledMenuItem(text: String(format: L("Overage Requests: %.0f"), overageRequests)))

            submenu.addItem(NSMenuItem.separator())
            let historyItem = NSMenuItem(title: L("Usage History"), action: nil, keyEquivalent: "")
            historyItem.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Usage History")
            debugLog("updateMultiProviderMenu: calling createCopilotHistorySubmenu")
            historyItem.submenu = createCopilotHistorySubmenu()
            debugLog("updateMultiProviderMenu: createCopilotHistorySubmenu completed")
            submenu.addItem(historyItem)

            submenu.addItem(NSMenuItem.separator())

            if let email = details.email {
                submenu.addItem(createDisabledMenuItem(
                    text: String(format: L("Account: %@"), PrivacyRedactor.display(email)),
                    icon: NSImage(systemSymbolName: "person.circle", accessibilityDescription: "User Account")
                ))
            }

            if let authSource = details.authSource {
                let authItem = NSMenuItem()
                authItem.view = createDisabledLabelView(
                    text: String(format: L("Token From: %@"), PrivacyRedactor.display(authSource)),
                    icon: NSImage(systemSymbolName: "key", accessibilityDescription: "Auth Source"),
                    multiline: true
                )
                submenu.addItem(authItem)
            }

            addOnItem.submenu = submenu
            menu.insertItem(addOnItem, at: insertIndex)
            insertIndex += 1
            debugLog("updateMultiProviderMenu: Copilot Add-on inserted with cost $\(overageCost)")
            return
        }

        if loadingProviders.contains(.copilot) {
            hasPayAsYouGo = true
            let item = NSMenuItem(title: L("Copilot Add-on (Loading...)"), action: nil, keyEquivalent: "")
            item.image = iconForProvider(.copilot)
            item.isEnabled = false
            item.tag = 999
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }
    }

    private func insertOrderedQuotaItems(at insertIndex: inout Int, hasQuota: inout Bool) {
        let quotaOrder = AppPreferences.shared.statusBarSettingsOrder(
            for: .subscription,
            providers: AppPreferences.statusBarSubscriptionProviders
        )
        debugLog("updateMultiProviderMenu: quota order=[\(quotaOrder.map { $0.rawValue }.joined(separator: ", "))]")

        var deferredUnavailableItems: [NSMenuItem] = []
        var deferredUnavailableProviders: [ProviderIdentifier] = []

        for identifier in quotaOrder {
            insertQuotaProviderMenuItems(
                identifier,
                at: &insertIndex,
                hasQuota: &hasQuota,
                deferredUnavailableItems: &deferredUnavailableItems,
                deferredUnavailableProviders: &deferredUnavailableProviders
            )
        }

        if !deferredUnavailableItems.isEmpty {
            let deferredNames = deferredUnavailableProviders.map { $0.displayName }.joined(separator: ", ")
            debugLog("updateMultiProviderMenu: inserting \(deferredUnavailableItems.count) deferred unavailable item(s) after ordered quota items: [\(deferredNames)]")
            for item in deferredUnavailableItems {
                menu.insertItem(item, at: insertIndex)
                insertIndex += 1
            }
        }
    }

    private func insertQuotaProviderMenuItems(
        _ identifier: ProviderIdentifier,
        at insertIndex: inout Int,
        hasQuota: inout Bool,
        deferredUnavailableItems: inout [NSMenuItem],
        deferredUnavailableProviders: inout [ProviderIdentifier]
    ) {
        guard isProviderEnabled(identifier) else { return }

        if identifier == .copilot {
            insertCopilotQuotaMenuItems(at: &insertIndex, hasQuota: &hasQuota)
            return
        }

        if identifier == .geminiCLI {
            insertGeminiQuotaMenuItems(
                at: &insertIndex,
                hasQuota: &hasQuota,
                deferredUnavailableItems: &deferredUnavailableItems,
                deferredUnavailableProviders: &deferredUnavailableProviders
            )
            return
        }

        let result = providerResults[identifier]
        let errorMessage = lastProviderErrors[identifier]

        if let errorMessage,
           shouldDisplayErrorStateEvenWithResult(errorMessage, identifier: identifier, result: result) {
            hasQuota = true
            let item = createErrorMenuItem(identifier: identifier, errorMessage: errorMessage)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: identifier, result: result, errorMessage: errorMessage)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if let result {
            if let accounts = result.accounts, !accounts.isEmpty {
                let authLabels = Set(
                    accounts.map { account in
                        authSourceLabel(for: account.details?.authSource, provider: identifier) ?? "Unknown"
                    }
                )
                let showAuthLabel = authLabels.count > 1
                let baseName = multiAccountBaseName(for: identifier)
                let codexEmailByAccountId: [String: String]
                if identifier == .codex {
                    codexEmailByAccountId = Dictionary(
                        uniqueKeysWithValues: TokenManager.shared.getOpenAIAccounts().compactMap { account in
                            guard let accountId = account.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !accountId.isEmpty,
                                  let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !email.isEmpty else {
                                return nil
                            }
                            return (accountId, email)
                        }
                    )
                } else {
                    codexEmailByAccountId = [:]
                }

                for account in accounts {
                    hasQuota = true
                    var displayName = accounts.count > 1 ? "\(baseName) #\(account.accountIndex + 1)" : baseName

                    let detailsEmail = account.details?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let accountEmail: String?
                    if identifier == .claude, let detailsEmail, !detailsEmail.isEmpty {
                        accountEmail = detailsEmail
                    } else if identifier == .codex, let detailsEmail, !detailsEmail.isEmpty {
                        accountEmail = detailsEmail
                    } else if identifier == .codex,
                              let accountId = account.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !accountId.isEmpty,
                              let mappedEmail = codexEmailByAccountId[accountId],
                              !mappedEmail.isEmpty {
                        accountEmail = mappedEmail
                    } else if identifier == .codex,
                              let fallbackEmail = codexEmailByAccountId.values.first,
                              accounts.count == 1 {
                        accountEmail = fallbackEmail
                    } else {
                        accountEmail = nil
                    }

                    if let accountEmail {
                        let displayEmail = PrivacyRedactor.display(accountEmail)
                        if accounts.count > 1 {
                            displayName += " (\(displayEmail))"
                        } else {
                            displayName = "\(baseName) (\(displayEmail))"
                        }
                    } else if accounts.count > 1, showAuthLabel {
                        let sourceLabel = authSourceLabel(for: account.details?.authSource, provider: identifier) ?? "Unknown"
                        displayName += " (\(PrivacyRedactor.display(sourceLabel)))"
                    }

                    let unavailableLabel = unavailableUsageSuffix(for: account, identifier: identifier)
                    if let unavailableLabel {
                        displayName += " (\(unavailableLabel))"
                    }
                    let isUnavailableRateLimited = unavailableLabel == L("Rate limited")

                    let usedPercents = quotaUsedPercents(identifier: identifier, account: account, result: nil)

                    let item = createNativeQuotaMenuItem(
                        name: displayName,
                        usedPercents: usedPercents,
                        icon: iconForProvider(identifier),
                        isEnabled: !isUnavailableRateLimited
                    )
                    item.tag = 999

                    if item.isEnabled,
                       let details = account.details,
                       details.hasAnyValue {
                        item.submenu = createDetailSubmenu(details, identifier: identifier, accountId: account.subscriptionId)
                    }

                    menu.insertItem(item, at: insertIndex)
                    insertIndex += 1
                }
                return
            }

            if case .quotaBased(let remaining, let entitlement, _) = result.usage {
                hasQuota = true
                let singlePercent = entitlement > 0 ? (Double(entitlement - remaining) / Double(entitlement)) * 100 : 0
                let usedPercents = quotaUsedPercents(identifier: identifier, account: nil, result: result, fallbackSinglePercent: singlePercent)

                let item = createNativeQuotaMenuItem(
                    name: identifier.displayName,
                    usedPercents: usedPercents,
                    icon: iconForProvider(identifier)
                )
                item.tag = 999

                if let details = result.details, details.hasAnyValue {
                    item.submenu = createDetailSubmenu(details, identifier: identifier)
                }

                menu.insertItem(item, at: insertIndex)
                insertIndex += 1
                return
            }
        }

        if let errorMessage {
            guard shouldDisplayErrorMenuItem(errorMessage) else {
                debugLog("updateMultiProviderMenu: hiding \(identifier.displayName) quota row because credentials are unavailable")
                return
            }
            hasQuota = true
            let item = createErrorMenuItem(identifier: identifier, errorMessage: errorMessage)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: identifier, result: nil, errorMessage: errorMessage)
            }
            let status = errorMenuStatus(for: errorMessage)
            if status.shouldDeferToBottom {
                deferredUnavailableItems.append(item)
                deferredUnavailableProviders.append(identifier)
                debugLog("updateMultiProviderMenu: deferred \(status.title) item for \(identifier.displayName)")
            } else {
                menu.insertItem(item, at: insertIndex)
                insertIndex += 1
            }
            return
        }

        if loadingProviders.contains(identifier) {
            hasQuota = true
            let item = NSMenuItem(title: String(format: L("%@ (Loading...)"), identifier.displayName), action: nil, keyEquivalent: "")
            item.image = iconForProvider(identifier)
            item.isEnabled = false
            item.tag = 999
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }
    }

    private func insertCopilotQuotaMenuItems(at insertIndex: inout Int, hasQuota: inout Bool) {
        let copilotResult = providerResults[.copilot]
        let copilotError = lastProviderErrors[.copilot]

        if let copilotError,
           shouldDisplayErrorStateEvenWithResult(copilotError, identifier: .copilot, result: copilotResult) {
            hasQuota = true
            let item = createErrorMenuItem(identifier: .copilot, errorMessage: copilotError)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: .copilot, result: copilotResult, errorMessage: copilotError)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if let copilotResult,
           let accounts = copilotResult.accounts,
           !accounts.isEmpty,
           isProviderEnabled(.copilot) {
            let copilotAuthLabels = Set(
                accounts.map { account in
                    authSourceLabel(for: account.details?.authSource, provider: .copilot) ?? L("Unknown")
                }
            )
            let showCopilotAuthLabel = copilotAuthLabels.count > 1
            let baseName = multiAccountBaseName(for: .copilot)
            for account in accounts {
                hasQuota = true
                let accountIdentifier: String
                if let accountId = account.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !accountId.isEmpty {
                    accountIdentifier = PrivacyRedactor.display(accountId)
                } else {
                    accountIdentifier = "#\(account.accountIndex + 1)"
                }
                var displayName = accounts.count > 1 ? "\(baseName) (\(accountIdentifier))" : baseName
                if accounts.count > 1, showCopilotAuthLabel {
                    let sourceLabel = authSourceLabel(for: account.details?.authSource, provider: .copilot) ?? L("Unknown")
                    displayName += " - \(PrivacyRedactor.display(sourceLabel))"
                }
                let unavailableLabel = unavailableUsageSuffix(for: account, identifier: .copilot)
                if let unavailableLabel {
                    displayName += " (\(unavailableLabel))"
                }
                let isUnavailableRateLimited = unavailableLabel == L("Rate limited")
                let quotaItem = createNativeQuotaMenuItem(
                    name: displayName,
                    usedPercent: account.usage.usagePercentage,
                    icon: iconForProvider(.copilot),
                    isEnabled: !isUnavailableRateLimited
                )
                quotaItem.tag = 999

                if quotaItem.isEnabled,
                   let details = account.details,
                   details.hasAnyValue {
                    quotaItem.submenu = createDetailSubmenu(details, identifier: .copilot, accountId: account.subscriptionId)
                }

                menu.insertItem(quotaItem, at: insertIndex)
                insertIndex += 1
            }
            return
        }

        if let copilotError {
            guard shouldDisplayErrorMenuItem(copilotError) else {
                debugLog("updateMultiProviderMenu: hiding Copilot quota row because credentials are unavailable")
                return
            }
            hasQuota = true
            let item = createErrorMenuItem(identifier: .copilot, errorMessage: copilotError)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: .copilot, result: nil, errorMessage: copilotError)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if loadingProviders.contains(.copilot) {
            hasQuota = true
            let item = NSMenuItem(title: String(format: L("%@ (Loading...)"), ProviderIdentifier.copilot.displayName), action: nil, keyEquivalent: "")
            item.image = iconForProvider(.copilot)
            item.isEnabled = false
            item.tag = 999
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if isProviderEnabled(.copilot), let copilotUsage = currentUsage {
            hasQuota = true
            let limit = copilotUsage.userPremiumRequestEntitlement
            let used = copilotUsage.usedRequests
            let usedPercent = limit > 0 ? (Double(used) / Double(limit)) * 100 : 0

            let quotaItem = createNativeQuotaMenuItem(
                name: ProviderIdentifier.copilot.displayName,
                usedPercent: usedPercent,
                icon: iconForProvider(.copilot)
            )
            quotaItem.tag = 999

            if let details = providerResults[.copilot]?.details, details.hasAnyValue {
                quotaItem.submenu = createDetailSubmenu(details, identifier: .copilot)
            } else {
                let submenu = NSMenu()
                let filledBlocks = Int((Double(used) / Double(max(limit, 1))) * 10)
                let emptyBlocks = 10 - filledBlocks
                let progressBar = String(repeating: "═", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                submenu.addItem(createDisabledMenuItem(text: "[\(progressBar)] \(used)/\(limit)"))
                submenu.addItem(createDisabledMenuItem(text: String(format: L("Monthly Usage: %.0f%%"), usedPercent)))

                if let resetDate = copilotUsage.quotaResetDateUTC {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    formatter.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
                    let paceInfo = calculateMonthlyPace(usagePercent: usedPercent, resetDate: resetDate)
                    let paceItem = NSMenuItem()
                    paceItem.view = createPaceView(paceInfo: paceInfo)
                    submenu.addItem(paceItem)

                    submenu.addItem(createDisabledMenuItem(
                        text: String(format: L("Resets: %@ UTC"), formatter.string(from: resetDate))
                    ))
                    debugLog("updateMultiProviderMenu: reset row tone aligned with pace text for copilot fallback")
                }

                submenu.addItem(NSMenuItem.separator())

                if let planName = copilotUsage.planDisplayName {
                    submenu.addItem(createDisabledMenuItem(
                        text: String(format: L("Plan: %@"), planName),
                        icon: NSImage(systemSymbolName: "crown", accessibilityDescription: "Plan")
                    ))
                }

                submenu.addItem(createDisabledMenuItem(text: String(format: L("Quota Limit: %@"), String(limit))))

                submenu.addItem(NSMenuItem.separator())

                if let email = providerResults[.copilot]?.details?.email {
                    submenu.addItem(createDisabledMenuItem(
                        text: String(format: L("Email: %@"), PrivacyRedactor.display(email)),
                        icon: NSImage(systemSymbolName: "person.circle", accessibilityDescription: "User Email")
                    ))
                }

                let authItem = NSMenuItem()
                authItem.view = createDisabledLabelView(
                    text: String(format: L("Token From: %@"), PrivacyRedactor.display("Browser Cookies (Chrome/Brave/Arc/Edge)")),
                    icon: NSImage(systemSymbolName: "key", accessibilityDescription: "Auth Source"),
                    multiline: true
                )
                submenu.addItem(authItem)

                quotaItem.submenu = submenu
            }

            menu.insertItem(quotaItem, at: insertIndex)
            insertIndex += 1
        }
    }

    private func insertGeminiQuotaMenuItems(
        at insertIndex: inout Int,
        hasQuota: inout Bool,
        deferredUnavailableItems: inout [NSMenuItem],
        deferredUnavailableProviders: inout [ProviderIdentifier]
    ) {
        guard isProviderEnabled(.geminiCLI) else { return }

        let geminiResult = providerResults[.geminiCLI]
        let geminiError = lastProviderErrors[.geminiCLI]

        if let geminiError,
           shouldDisplayErrorStateEvenWithResult(geminiError, identifier: .geminiCLI, result: geminiResult) {
            hasQuota = true
            let item = createErrorMenuItem(identifier: .geminiCLI, errorMessage: geminiError)
            if item.isEnabled {
                item.submenu = createErrorSubmenu(identifier: .geminiCLI, result: geminiResult, errorMessage: geminiError)
            }
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
            return
        }

        if let result = geminiResult,
           let details = result.details,
           let geminiAccounts = details.geminiAccounts,
           !geminiAccounts.isEmpty {
            let geminiAuthLabels = Set(
                geminiAccounts.map { account in
                    authSourceLabel(for: account.authSource, provider: .geminiCLI) ?? L("Unknown")
                }
            )
            let showGeminiAuthLabel = geminiAuthLabels.count > 1

            for account in geminiAccounts {
                hasQuota = true
                let accountNumber = account.accountIndex + 1
                let usedPercent = normalizedUsagePercent(100.0 - account.remainingPercentage) ?? 0.0
                let normalizedEmail = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
                var displayName = "Gemini CLI"

                if !normalizedEmail.isEmpty, normalizedEmail.lowercased() != "unknown" {
                    displayName = "Gemini CLI (\(PrivacyRedactor.display(normalizedEmail)))"
                } else if geminiAccounts.count > 1, showGeminiAuthLabel {
                    displayName = "Gemini CLI #\(accountNumber)"
                    let sourceLabel = authSourceLabel(for: account.authSource, provider: .geminiCLI) ?? L("Unknown")
                    displayName += " (\(PrivacyRedactor.display(sourceLabel)))"
                } else if geminiAccounts.count > 1 {
                    displayName = "Gemini CLI #\(accountNumber)"
                }

                let item = createNativeQuotaMenuItem(
                    name: displayName,
                    usedPercents: [usedPercent],
                    icon: iconForProvider(.geminiCLI)
                )
                item.tag = 999
                item.submenu = createGeminiAccountSubmenu(account)
                menu.insertItem(item, at: insertIndex)
                insertIndex += 1
            }
            return
        }

        if let errorMessage = geminiError {
            if shouldDisplayErrorMenuItem(errorMessage) {
                hasQuota = true
                let item = createErrorMenuItem(identifier: .geminiCLI, errorMessage: errorMessage)
                if item.isEnabled {
                    item.submenu = createErrorSubmenu(identifier: .geminiCLI, result: nil, errorMessage: errorMessage)
                }
                let status = errorMenuStatus(for: errorMessage)
                if status.shouldDeferToBottom {
                    deferredUnavailableItems.append(item)
                    deferredUnavailableProviders.append(.geminiCLI)
                    debugLog("updateMultiProviderMenu: deferred \(status.title) item for Gemini CLI")
                } else {
                    menu.insertItem(item, at: insertIndex)
                    insertIndex += 1
                }
            } else {
                debugLog("updateMultiProviderMenu: hiding Gemini CLI row because credentials are unavailable")
            }
            return
        }

        if loadingProviders.contains(.geminiCLI) {
            hasQuota = true
            let item = NSMenuItem(title: String(format: L("%@ (Loading...)"), ProviderIdentifier.geminiCLI.displayName), action: nil, keyEquivalent: "")
            item.image = iconForProvider(.geminiCLI)
            item.isEnabled = false
            item.tag = 999
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }
    }

    private func quotaUsedPercents(
        identifier: ProviderIdentifier,
        account: ProviderAccountResult?,
        result: ProviderResult?,
        fallbackSinglePercent: Double? = nil
    ) -> [Double] {
        if identifier == .claude {
            let details = account?.details ?? result?.details
            if let fiveHour = details?.fiveHourUsage,
               let sevenDay = details?.sevenDayUsage {
                var percents = [fiveHour, sevenDay]
                if let sonnetUsage = details?.sonnetUsage {
                    percents.append(sonnetUsage)
                }
                return percents
            }
        }

        if identifier == .minimaxCodingPlan {
            let details = account?.details ?? result?.details
            if let fiveHour = details?.fiveHourUsage,
               let sevenDay = details?.sevenDayUsage {
                return [fiveHour, sevenDay]
            }
        }

        if identifier == .kimi {
            let details = account?.details ?? result?.details
            if let fiveHour = details?.fiveHourUsage,
               let sevenDay = details?.sevenDayUsage {
                return [fiveHour, sevenDay]
            }
        }

        if identifier == .codex {
            let details = account?.details ?? result?.details
            var percents = [account?.usage.usagePercentage ?? fallbackSinglePercent ?? 0]
            if let secondary = details?.secondaryUsage {
                percents.append(secondary)
            }
            if let sparkPrimary = details?.sparkUsage {
                percents.append(sparkPrimary)
            }
            if let sparkSecondary = details?.sparkSecondaryUsage {
                percents.append(sparkSecondary)
            }
            return percents
        }

        if identifier == .zaiCodingPlan {
            let details = account?.details ?? result?.details
            let percents = [details?.tokenUsagePercent, details?.mcpUsagePercent].compactMap { $0 }
            return percents.isEmpty ? [account?.usage.usagePercentage ?? fallbackSinglePercent ?? 0] : percents
        }

        if identifier == .chutes {
            let details = account?.details ?? result?.details
            let percents = [dailyPercentFromDetails(details), chutesMonthlyPercentFromDetails(details)].compactMap { $0 }
            return percents.isEmpty ? [account?.usage.usagePercentage ?? fallbackSinglePercent ?? 0] : percents
        }

        if identifier == .nanoGpt {
            let details = account?.details ?? result?.details
            let percents = [details?.sevenDayUsage, details?.tokenUsagePercent, details?.mcpUsagePercent].compactMap { $0 }
            return percents.isEmpty ? [account?.usage.usagePercentage ?? fallbackSinglePercent ?? 0] : percents
        }

        if let account {
            return [account.usage.usagePercentage]
        }

        return [fallbackSinglePercent ?? result?.usage.usagePercentage ?? 0]
    }

    private func multiAccountBaseName(for identifier: ProviderIdentifier) -> String {
        switch identifier {
        case .codex:
            return "ChatGPT"
        default:
            return identifier.displayName
        }
    }

    private func authSourceLabel(for authSource: String?, provider: ProviderIdentifier) -> String? {
        guard let authSource, !authSource.isEmpty else { return nil }

        func parseSingleSource(_ rawSource: String) -> String? {
            let lowercased = rawSource.lowercased()

            if lowercased.contains("opencode") {
                return "OpenCode"
            }

            switch provider {
            case .codex:
                if lowercased.contains("usagebar codex accounts") {
                    return "UsageBar Codex Accounts"
                }
                if lowercased.contains(".codex-lb") || lowercased.contains("/codex-lb/") || lowercased.contains("codex lb") {
                    return "Codex LB"
                }
                if lowercased.contains(".codex") || lowercased.contains("/codex/") || lowercased == "codex" {
                    return "Codex"
                }
            case .claude:
                if lowercased.contains("claude code (keychain)") || lowercased.contains("keychain") {
                    return "Claude Code (Keychain)"
                }
                if lowercased.contains("claude code (legacy)") || lowercased.contains(".credentials.json") || lowercased.contains(".claude") {
                    return "Claude Code (Legacy)"
                }
                if lowercased.contains("claude-code") || lowercased.contains("claude code") {
                    return "Claude Code"
                }
            case .copilot:
                if lowercased.contains("browser cookies") {
                    return "Browser Cookies"
                }
                if lowercased.contains("github-copilot") {
                    if lowercased.contains("hosts.json") {
                        return "VS Code (hosts.json)"
                    }
                    if lowercased.contains("apps.json") {
                        return "VS Code (apps.json)"
                    }
                    return "VS Code"
                }
            case .geminiCLI:
                if lowercased.contains("antigravity") {
                    return "Antigravity"
                }
                if lowercased.contains(".gemini/oauth_creds.json")
                    || lowercased.contains("/.gemini/oauth_creds.json")
                    || lowercased.contains("oauth_creds.json") {
                    return "Gemini CLI"
                }
            default:
                break
            }

            if lowercased.contains("keychain") {
                return "Keychain"
            }

            return nil
        }

        let parts = authSource
            .components(separatedBy: CharacterSet(charactersIn: ",;|"))
            .flatMap { $0.components(separatedBy: " + ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceParts = parts.isEmpty ? [authSource] : parts
        var labels: [String] = []
        for part in sourceParts {
            guard let label = parseSingleSource(part), !labels.contains(label) else { continue }
            labels.append(label)
        }

        if labels.isEmpty {
            return parseSingleSource(authSource)
        }
        if labels.count == 1 {
            return labels.first
        }
        return labels.joined(separator: " + ")
    }

    private func colorForRemainingPercent(_ remaining: Double) -> NSColor {
        if remaining <= 10 {
            return .systemRed
        } else if remaining <= 30 {
            return .systemOrange
        } else {
            return .secondaryLabelColor
        }
    }

    private func createNativeQuotaMenuItem(
        name: String,
        usedPercents: [Double],
        icon: NSImage?,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let attributed = NSMutableAttributedString()
        let primaryColor = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        let secondaryColor = isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor

        attributed.append(NSAttributedString(
            string: "\(name)",
            attributes: [.font: MenuDesignToken.Typography.defaultFont, .foregroundColor: primaryColor]
        ))

        let defaultFontUsagePercent: NSFont = MenuDesignToken.Typography.monospacedFont
        attributed.append(NSAttributedString(
            string: ": ",
            attributes: [.font: defaultFontUsagePercent, .foregroundColor: secondaryColor]
        ))

        for (index, usedPercent) in usedPercents.enumerated() {
            let remainingPercent = max(0.0, 100.0 - usedPercent)
            let percentText = UsagePercentDisplayFormatter.string(from: remainingPercent)
            let percentColor = isEnabled ? colorForRemainingPercent(remainingPercent) : NSColor.disabledControlTextColor
            let font: NSFont = isEnabled && usedPercent >= 100
                ? MenuDesignToken.Typography.monospacedBoldFont
                : defaultFontUsagePercent

            attributed.append(NSAttributedString(
                string: percentText,
                attributes: [.font: font, .foregroundColor: percentColor]
            ))

            if index < usedPercents.count - 1 {
                attributed.append(NSAttributedString(
                    string: ", ",
                    attributes: [.font: defaultFontUsagePercent, .foregroundColor: secondaryColor]
                ))
            }
        }

        attributed.append(NSAttributedString(
            string: L(" left"),
            attributes: [.font: defaultFontUsagePercent, .foregroundColor: secondaryColor]
        ))

        let item = NSMenuItem()
        item.attributedTitle = attributed
        item.image = icon
        item.isEnabled = isEnabled

        if let icon {
            if !isEnabled {
                item.image = tintedImage(icon, color: .disabledControlTextColor)
            } else {
                let minRemaining = usedPercents.map { max(0.0, 100.0 - $0) }.min() ?? 100.0
                if minRemaining <= 30 {
                    let iconColor: NSColor = minRemaining <= 10 ? .systemRed : .systemOrange
                    item.image = tintedImage(icon, color: iconColor)
                }
            }
        }

        return item
    }

    private func createNativeQuotaMenuItem(
        name: String,
        usedPercent: Double,
        icon: NSImage?,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        createNativeQuotaMenuItem(name: name, usedPercents: [usedPercent], icon: icon, isEnabled: isEnabled)
    }

    private func unavailableUsageSuffix(for account: ProviderAccountResult, identifier: ProviderIdentifier) -> String? {
        guard (account.usage.totalEntitlement ?? 0) == 0 else { return nil }

        if let authErrorMessage = account.details?.authErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authErrorMessage.isEmpty {
            let lowercased = authErrorMessage.lowercased()
            if lowercased.contains("token expired")
                || lowercased.contains("refresh")
                || lowercased.contains("auth")
                || lowercased.contains("401")
                || lowercased.contains("403") {
                return L("Token expired")
            }

            if identifier == .claude, lowercased.contains("rate limited") {
                return L("Rate limited")
            }
        }

        return L("No usage data")
    }

    private func isAuthenticationError(_ errorMessage: String) -> Bool {
        let authPatterns = [
            "Authentication failed",
            "not found",
            "not available",
            "access token",
            "API key",
            "No Gemini accounts",
            "credentials"
        ]
        let lowercased = errorMessage.lowercased()
        return authPatterns.contains { lowercased.contains($0.lowercased()) }
    }

    private func isRateLimitError(_ errorMessage: String) -> Bool {
        let lowercased = errorMessage.lowercased()
        return lowercased.contains("rate limited")
            || lowercased.contains("rate_limit_error")
            || lowercased.contains("http 429")
            || lowercased.contains("too many requests")
    }

    private func errorMenuStatus(for errorMessage: String) -> ErrorMenuStatus {
        let lowercased = errorMessage.lowercased()
        if isRateLimitError(errorMessage) {
            return .rateLimited
        }
        if lowercased.contains("subscription") {
            return .noSubscription
        }
        if isAuthenticationError(errorMessage) {
            return .noCredentials
        }
        return .error
    }

    private func shouldDisplayErrorStateEvenWithResult(_ errorMessage: String) -> Bool {
        switch errorMenuStatus(for: errorMessage) {
        case .rateLimited:
            return true
        case .noCredentials, .noSubscription, .error:
            return false
        }
    }

    private func shouldDisplayErrorMenuItem(_ errorMessage: String) -> Bool {
        errorMenuStatus(for: errorMessage).shouldDisplayInList
    }

    private func shouldDisplayErrorStateEvenWithResult(
        _ errorMessage: String,
        identifier: ProviderIdentifier,
        result: ProviderResult?
    ) -> Bool {
        guard shouldDisplayErrorStateEvenWithResult(errorMessage) else { return false }

        if ProviderDisplayPolicy.shouldShowRateLimitedErrorRow(
            identifier: identifier,
            errorMessage: errorMessage,
            result: result
        ) {
            return true
        }

        if ProviderDisplayPolicy.hasDisplayableAccountRows(identifier: identifier, result: result) {
            debugLog("Preserving account rows for \(identifier.displayName) despite rate limit cooldown because account data is available")
        }
        return false
    }

    private func createErrorMenuItem(identifier: ProviderIdentifier, errorMessage: String) -> NSMenuItem {
        let status = errorMenuStatus(for: errorMessage)
        let title = "\(identifier.displayName) (\(status.title))"

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let iconColor: NSColor = status.shouldDisableListItem ? .disabledControlTextColor : .systemOrange
        item.image = tintedImage(iconForProvider(identifier), color: iconColor)
        item.isEnabled = !status.shouldDisableListItem
        item.tag = 999
        item.toolTip = errorMessage

        return item
    }

    private func createErrorSubmenu(
        identifier: ProviderIdentifier,
        result: ProviderResult?,
        errorMessage: String
    ) -> NSMenu {
        let submenu = NSMenu()

        submenu.addItem(createDisabledMenuItem(text: String(format: L("Status: %@"), errorMenuStatus(for: errorMessage).title)))

        let errorItem = NSMenuItem()
        errorItem.view = createDisabledLabelView(text: String(format: L("Error: %@"), errorMessage), multiline: true)
        submenu.addItem(errorItem)

        if let result, let details = result.details, details.hasAnyValue {
            submenu.addItem(NSMenuItem.separator())

            let cachedItem = NSMenuItem(title: L("Cached Details"), action: nil, keyEquivalent: "")
            cachedItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: L("Cached Details"))
            cachedItem.submenu = createDetailSubmenu(details, identifier: identifier)
            submenu.addItem(cachedItem)
        }

        return submenu
    }
}
