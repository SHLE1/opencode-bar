import AppKit
import Foundation

extension StatusBarController {

    func createDetailSubmenu(_ details: DetailedUsage, identifier: ProviderIdentifier, accountId: String? = nil) -> NSMenu {
        let submenu = NSMenu()

        switch identifier {
        case .openRouter:
            if let remaining = details.creditsRemaining {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Credits: $%.0f"), remaining))
                submenu.addItem(item)
            }

        case .openCode:
            if let avg = details.avgCostPerDay {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Avg/Day: $%.2f"), avg))
                submenu.addItem(item)
            }
            if let sessions = details.sessions {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: sessions), number: .decimal)
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Sessions: %@"), formatted))
                submenu.addItem(item)
            }
            if let messages = details.messages {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: messages), number: .decimal)
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Messages: %@"), formatted))
                submenu.addItem(item)
            }

            if let models = details.modelBreakdown, !models.isEmpty {
                submenu.addItem(NSMenuItem.separator())
                let headerItem = NSMenuItem()
                headerItem.view = createDisabledLabelView(
                    text: L("Top Models"),
                    font: NSFont.systemFont(ofSize: 11, weight: .bold)
                )
                submenu.addItem(headerItem)

                let sortedModels = models.sorted { $0.value > $1.value }.prefix(5)
                for (model, cost) in sortedModels {
                    let shortName = model.components(separatedBy: "/").last ?? model
                    let item = NSMenuItem()
                    item.view = createDisabledLabelView(text: String(format: "  %@: $%.2f", shortName, cost))
                    submenu.addItem(item)
                }
            }

        case .copilot:
            if let used = details.copilotUsedRequests, let limit = details.copilotLimitRequests, limit > 0 {
                let isUnlimitedPlan = limit == Int.max
                let usageRatio = isUnlimitedPlan ? 0.0 : (Double(used) / Double(max(limit, 1)))
                let normalizedUsageRatio = min(max(usageRatio, 0), 1)
                let filledBlocks = Int(normalizedUsageRatio * 10)
                let emptyBlocks = 10 - filledBlocks
                let progressBar = String(repeating: "═", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                let limitText = isUnlimitedPlan ? L("Unlimited") : "\(limit)"
                let progressItem = NSMenuItem()
                progressItem.view = createDisabledLabelView(text: "[\(progressBar)] \(used)/\(limitText)")
                submenu.addItem(progressItem)

                let usagePercent = isUnlimitedPlan ? 0.0 : ((Double(used) / Double(limit)) * 100)
                let items = createUsageWindowRow(label: L("Monthly"), usagePercent: usagePercent, resetDate: details.copilotQuotaResetDateUTC, isMonthly: true)
                items.forEach { submenu.addItem($0) }
            } else {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: L("Usage data unavailable"))
                submenu.addItem(item)
            }

            submenu.addItem(NSMenuItem.separator())
            let planHeaderItem = NSMenuItem()
            planHeaderItem.view = createDisabledLabelView(
                text: L("Plan"),
                font: NSFont.systemFont(ofSize: 11, weight: .bold)
            )
            submenu.addItem(planHeaderItem)

            if let planText = resolvedPlanDisplayText(
                for: .copilot,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                let planItem = NSMenuItem()
                planItem.view = createDisabledLabelView(
                    text: planText,
                    icon: NSImage(systemSymbolName: "crown", accessibilityDescription: "Plan")
                )
                submenu.addItem(planItem)
            }

            if let limit = details.copilotLimitRequests {
                let freeItem = NSMenuItem()
                let limitText = (limit == Int.max) ? L("Unlimited") : "\(limit)"
                freeItem.view = createDisabledLabelView(text: String(format: L("Quota Limit: %@"), limitText))
                submenu.addItem(freeItem)
            }

            var accountItems: [(sfSymbol: String, text: String)] = []
            if let email = details.email {
                accountItems.append((sfSymbol: "person.circle", text: email))
            }
            accountItems.append(
                (
                    sfSymbol: "key",
                    text: String(format: L("Token From: %@"), details.authSource ?? "Browser Cookies (Chrome/Brave/Arc/Edge)")
                )
            )
            if !accountItems.isEmpty {
                createAccountInfoSection(items: accountItems).forEach { submenu.addItem($0) }
            }

        case .claude:
            if let fiveHour = details.fiveHourUsage {
                let items = createUsageWindowRow(
                    label: L("5h"),
                    usagePercent: fiveHour,
                    resetDate: details.fiveHourReset,
                    windowHours: 5
                )
                items.forEach { submenu.addItem($0) }
            }
            if details.fiveHourUsage != nil, details.sevenDayUsage != nil {
                submenu.addItem(NSMenuItem.separator())
            }
            if let sevenDay = details.sevenDayUsage {
                let items = createUsageWindowRow(
                    label: L("Weekly"),
                    usagePercent: sevenDay,
                    resetDate: details.sevenDayReset,
                    windowHours: 168
                )
                items.forEach { submenu.addItem($0) }
            }

            let hasModelBreakdown = details.sonnetUsage != nil || details.opusUsage != nil
            if hasModelBreakdown {
                submenu.addItem(NSMenuItem.separator())
            }
            if let sonnet = details.sonnetUsage {
                let sonnetReset = details.sonnetReset ?? details.sevenDayReset
                if details.sonnetReset == nil, sonnetReset != nil {
                    debugLog("createDetailSubmenu(claude): Sonnet reset missing, using Weekly reset fallback")
                }
                let items = createUsageWindowRow(
                    label: L("Sonnet (Weekly)"),
                    usagePercent: sonnet,
                    resetDate: sonnetReset,
                    windowHours: 168
                )
                items.forEach { submenu.addItem($0) }
            }
            if details.sonnetUsage != nil, details.opusUsage != nil {
                submenu.addItem(NSMenuItem.separator())
            }
            if let opus = details.opusUsage {
                let opusReset = details.opusReset ?? details.sevenDayReset
                if details.opusReset == nil, opusReset != nil {
                    debugLog("createDetailSubmenu(claude): Opus reset missing, using Weekly reset fallback")
                }
                let items = createUsageWindowRow(
                    label: L("Opus (Weekly)"),
                    usagePercent: opus,
                    resetDate: opusReset,
                    windowHours: 168
                )
                items.forEach { submenu.addItem($0) }
            }

            if let extraUsageEnabled = details.extraUsageEnabled {
                if details.sonnetUsage != nil || details.opusUsage != nil {
                    submenu.addItem(NSMenuItem.separator())
                }
                let statusItem = NSMenuItem()
                let extraUsageStatus = extraUsageEnabled ? L("Extra Usage: ON") : L("Extra Usage: OFF")
                statusItem.view = createDisabledLabelView(text: extraUsageStatus)
                submenu.addItem(statusItem)

                if extraUsageEnabled,
                   let limitUSD = details.extraUsageMonthlyLimitUSD,
                   limitUSD > 0 {
                    let usedUSD = details.extraUsageUsedUSD ?? 0
                    let percent = details.extraUsageUtilizationPercent ?? ((usedUSD / limitUSD) * 100)

                    let rows = createUsageWindowRow(label: L("Extra (Monthly)"), usagePercent: percent)
                    rows.forEach { submenu.addItem($0) }
                    debugLog("createDetailSubmenu(claude): rendering Extra Usage limit rows without left indent")

                    let limitItem = NSMenuItem()
                    limitItem.view = createDisabledLabelView(
                        text: String(format: L("Limit: $%.2f/m"), limitUSD)
                    )
                    submenu.addItem(limitItem)

                    let usedItem = NSMenuItem()
                    usedItem.view = createDisabledLabelView(
                        text: String(format: L("Used: $%.2f"), usedUSD)
                    )
                    submenu.addItem(usedItem)
                }
            }

            if let planText = resolvedPlanDisplayText(
                for: .claude,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }

            let claudeEmail = details.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let claudeAuthSource = details.authSource?.trimmingCharacters(in: .whitespacesAndNewlines)
            if (claudeEmail?.isEmpty == false) || (claudeAuthSource?.isEmpty == false) {
                var accountItems: [(sfSymbol: String, text: String)] = []
                if let claudeEmail, !claudeEmail.isEmpty {
                    accountItems.append((sfSymbol: "person.circle", text: claudeEmail))
                }
                if let claudeAuthSource, !claudeAuthSource.isEmpty {
                    accountItems.append((sfSymbol: "key", text: String(format: L("Token From: %@"), claudeAuthSource)))
                }
                createAccountInfoSection(items: accountItems).forEach { submenu.addItem($0) }
            }

        case .codex:
            let sparkLabel = {
                guard let rawLabel = details.sparkWindowLabel else { return "Spark" }
                let normalized = rawLabel
                    .replacingOccurrences(of: "_window", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return "Spark" }
                if normalized.lowercased() == normalized {
                    return normalized.capitalized
                }
                return normalized
            }()

            var baseUsageRows: [(label: String, usage: Double, resetDate: Date?, windowHours: Int?)] = []
            if let primary = details.dailyUsage {
                // Codex primary window is 5 hours.
                baseUsageRows.append((label: L("5h"), usage: primary, resetDate: details.primaryReset, windowHours: 5))
            }
            if let secondary = details.secondaryUsage {
                baseUsageRows.append((label: L("Weekly"), usage: secondary, resetDate: details.secondaryReset, windowHours: 168))
            }

            for (index, row) in baseUsageRows.enumerated() {
                if index > 0 {
                    submenu.addItem(NSMenuItem.separator())
                }
                let items = createUsageWindowRow(
                    label: row.label,
                    usagePercent: row.usage,
                    resetDate: row.resetDate,
                    windowHours: row.windowHours
                )
                items.forEach { submenu.addItem($0) }
            }

            var sparkUsageRows: [(label: String, usage: Double, resetDate: Date?, windowHours: Int?)] = []
            if let sparkPrimary = details.sparkUsage {
                sparkUsageRows.append((label: "5h (\(sparkLabel))", usage: sparkPrimary, resetDate: details.sparkReset, windowHours: 5))
            }
            if let sparkSecondary = details.sparkSecondaryUsage {
                sparkUsageRows.append((label: "\(L("Weekly")) (\(sparkLabel))", usage: sparkSecondary, resetDate: details.sparkSecondaryReset, windowHours: 168))
            }
            if !sparkUsageRows.isEmpty, !baseUsageRows.isEmpty {
                submenu.addItem(NSMenuItem.separator())
            }
            for (index, row) in sparkUsageRows.enumerated() {
                if index > 0 {
                    submenu.addItem(NSMenuItem.separator())
                }
                let items = createUsageWindowRow(
                    label: row.label,
                    usagePercent: row.usage,
                    resetDate: row.resetDate,
                    windowHours: row.windowHours
                )
                items.forEach { submenu.addItem($0) }
            }

            submenu.addItem(NSMenuItem.separator())
            let codexPlanHeader = NSMenuItem()
            codexPlanHeader.view = createDisabledLabelView(
                text: L("Plan"),
                font: NSFont.systemFont(ofSize: 11, weight: .bold)
            )
            submenu.addItem(codexPlanHeader)

            if let planText = resolvedPlanDisplayText(
                for: .codex,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(
                    text: planText,
                    icon: NSImage(systemSymbolName: "crown", accessibilityDescription: "Plan")
                )
                submenu.addItem(item)
            }
            if let credits = details.creditsBalance {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Credits: $%.2f"), credits))
                submenu.addItem(item)
            }

            let codexEmail = details.email ?? codexEmail(for: accountId)
            let codexAuthSource = details.authSource?.trimmingCharacters(in: .whitespacesAndNewlines)
            if codexEmail != nil || (codexAuthSource?.isEmpty == false) {
                var accountItems: [(sfSymbol: String, text: String)] = []
                if let email = codexEmail {
                    accountItems.append((sfSymbol: "person.circle", text: email))
                }
                if let codexAuthSource, !codexAuthSource.isEmpty {
                    accountItems.append((sfSymbol: "key", text: String(format: L("Token From: %@"), codexAuthSource)))
                }
                createAccountInfoSection(items: accountItems).forEach { submenu.addItem($0) }
            }

        case .geminiCLI:
            // modelBreakdown stores remaining% — convert to used% at display layer
            if let models = details.modelBreakdown, !models.isEmpty {
                addGroupedModelUsageSection(
                    to: submenu,
                    modelBreakdown: models,
                    modelResetTimes: details.modelResetTimes,
                    paceWindowHours: 24,
                    debugContext: "createDetailSubmenu(gemini_cli \(details.email ?? "unknown"))"
                )
            }

            if let planText = resolvedPlanDisplayText(
                for: .geminiCLI,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }

            let geminiEmail = details.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let geminiAuthSource = details.authSource?.trimmingCharacters(in: .whitespacesAndNewlines)
            if (geminiEmail?.isEmpty == false) || (geminiAuthSource?.isEmpty == false) {
                var accountItems: [(sfSymbol: String, text: String)] = []
                if let geminiEmail, !geminiEmail.isEmpty {
                    accountItems.append((sfSymbol: "person.circle", text: geminiEmail))
                }
                if let geminiAuthSource, !geminiAuthSource.isEmpty {
                    accountItems.append((sfSymbol: "key", text: String(format: L("Token From: %@"), geminiAuthSource)))
                }
                createAccountInfoSection(items: accountItems).forEach { submenu.addItem($0) }
            }

        case .antigravity:
            // modelBreakdown stores remaining% — convert to used% at display layer
            if let models = details.modelBreakdown, !models.isEmpty {
                addGroupedModelUsageSection(
                    to: submenu,
                    modelBreakdown: models,
                    modelResetTimes: details.modelResetTimes,
                    paceWindowHours: 24,
                    debugContext: "createDetailSubmenu(antigravity \(details.email ?? "unknown"))"
                )
            }

            var antigravityAccountItems: [(sfSymbol: String, text: String)] = []
            if let planText = resolvedPlanDisplayText(
                for: .antigravity,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                antigravityAccountItems.append((sfSymbol: "crown", text: planText))
            }
            if let email = details.email {
                antigravityAccountItems.append((sfSymbol: "person.circle", text: email))
            }
            if let authSource = details.authSource?.trimmingCharacters(in: .whitespacesAndNewlines),
               !authSource.isEmpty {
                antigravityAccountItems.append((sfSymbol: "key", text: String(format: L("Token From: %@"), authSource)))
            }
            if !antigravityAccountItems.isEmpty {
                createAccountInfoSection(items: antigravityAccountItems).forEach { submenu.addItem($0) }
            }

        case .kimi:
            if let fiveHour = details.fiveHourUsage {
                let items = createUsageWindowRow(
                    label: L("5h"),
                    usagePercent: fiveHour,
                    resetDate: details.fiveHourReset,
                    windowHours: 5
                )
                items.forEach { submenu.addItem($0) }
            }
            if details.fiveHourUsage != nil, details.sevenDayUsage != nil {
                submenu.addItem(NSMenuItem.separator())
            }
            if let weekly = details.sevenDayUsage {
                let items = createUsageWindowRow(
                    label: L("Weekly"),
                    usagePercent: weekly,
                    resetDate: details.sevenDayReset,
                    windowHours: 168
                )
                items.forEach { submenu.addItem($0) }
            }

            if let plan = details.planType {
                submenu.addItem(NSMenuItem.separator())
                let kimiPlanHeader = NSMenuItem()
                kimiPlanHeader.view = createDisabledLabelView(
                    text: L("Plan"),
                    font: NSFont.systemFont(ofSize: 11, weight: .bold)
                )
                submenu.addItem(kimiPlanHeader)

                let item = NSMenuItem()
                item.view = createDisabledLabelView(
                    text: resolvedPlanDisplayText(
                        for: .kimi,
                        rawPlanName: plan,
                        accountId: accountId,
                        email: details.email
                    ) ?? plan,
                    icon: NSImage(systemSymbolName: "crown", accessibilityDescription: "Plan")
                )
                submenu.addItem(item)
            }

        case .minimaxCodingPlan:
            if let fiveHour = details.fiveHourUsage {
                let items = createUsageWindowRow(
                    label: L("5h"),
                    usagePercent: fiveHour,
                    resetDate: details.fiveHourReset,
                    windowHours: 5
                )
                items.forEach { submenu.addItem($0) }
            }
            if details.fiveHourUsage != nil, details.sevenDayUsage != nil {
                submenu.addItem(NSMenuItem.separator())
            }
            if let weekly = details.sevenDayUsage {
                let items = createUsageWindowRow(
                    label: L("Weekly"),
                    usagePercent: weekly,
                    resetDate: details.sevenDayReset,
                    windowHours: 168
                )
                items.forEach { submenu.addItem($0) }
            }

            if let planText = resolvedPlanDisplayText(
                for: .minimaxCodingPlan,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }

        case .zaiCodingPlan:
            if let tokenUsage = details.tokenUsagePercent {
                let items = createUsageWindowRow(
                    label: L("Tokens (5h)"),
                    usagePercent: tokenUsage,
                    resetDate: details.tokenUsageReset,
                    windowHours: 5
                )
                items.forEach { submenu.addItem($0) }
            }
            if let tokenUsed = details.tokenUsageUsed, let tokenTotal = details.tokenUsageTotal {
                let item = createLimitRow(label: L("Tokens"), used: Double(tokenUsed), total: Double(tokenTotal))
                submenu.addItem(item)
            }

            if let mcpUsage = details.mcpUsagePercent {
                let items = createUsageWindowRow(
                    label: L("MCP (Monthly)"),
                    usagePercent: mcpUsage,
                    resetDate: details.mcpUsageReset,
                    isMonthly: true
                )
                items.forEach { submenu.addItem($0) }
            }
            if let mcpUsed = details.mcpUsageUsed, let mcpTotal = details.mcpUsageTotal {
                let item = createLimitRow(label: L("MCP"), used: Double(mcpUsed), total: Double(mcpTotal))
                submenu.addItem(item)
            }

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 0

            if details.modelUsageTokens != nil || details.modelUsageCalls != nil {
                submenu.addItem(NSMenuItem.separator())
                let headerItem = NSMenuItem()
                headerItem.view = createDisabledLabelView(
                    text: L("Last 24h"),
                    font: NSFont.systemFont(ofSize: 11, weight: .bold)
                )
                submenu.addItem(headerItem)
            }

            if let tokens = details.modelUsageTokens {
                let tokensText = numberFormatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Tokens Used: %@"), tokensText))
                submenu.addItem(item)
            }

            if let calls = details.modelUsageCalls {
                let callsText = numberFormatter.string(from: NSNumber(value: calls)) ?? "\(calls)"
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Model Calls: %@"), callsText))
                submenu.addItem(item)
            }

            if details.toolNetworkSearchCount != nil || details.toolWebReadCount != nil || details.toolZreadCount != nil {
                submenu.addItem(NSMenuItem.separator())
                let headerItem = NSMenuItem()
                headerItem.view = createDisabledLabelView(
                    text: L("Tool Usage (24h)"),
                    font: NSFont.systemFont(ofSize: 11, weight: .bold)
                )
                submenu.addItem(headerItem)
            }

            if let networkSearch = details.toolNetworkSearchCount {
                let countText = numberFormatter.string(from: NSNumber(value: networkSearch)) ?? "\(networkSearch)"
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Network Search: %@"), countText))
                submenu.addItem(item)
            }

            if let webRead = details.toolWebReadCount {
                let countText = numberFormatter.string(from: NSNumber(value: webRead)) ?? "\(webRead)"
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Web Read: %@"), countText))
                submenu.addItem(item)
            }

            if let zread = details.toolZreadCount {
                let countText = numberFormatter.string(from: NSNumber(value: zread)) ?? "\(zread)"
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("ZRead: %@"), countText))
                submenu.addItem(item)
            }

            if let planText = resolvedPlanDisplayText(
                for: .zaiCodingPlan,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }

        case .nanoGpt:
            if let weeklyUsage = details.sevenDayUsage {
                let rows = createUsageWindowRow(
                    label: L("Weekly Input Tokens"),
                    usagePercent: weeklyUsage,
                    resetDate: details.sevenDayReset,
                    windowHours: 24 * 7
                )
                rows.forEach { submenu.addItem($0) }
            }

            if details.creditsBalance != nil || details.totalCredits != nil {
                submenu.addItem(NSMenuItem.separator())
            }

            if let usdBalance = details.creditsBalance {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("USD Balance: $%.2f"), usdBalance))
                submenu.addItem(item)
            }

            if let nanoBalance = details.totalCredits {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("NANO Balance: %.8f"), nanoBalance))
                submenu.addItem(item)
            }

            if let planText = resolvedPlanDisplayText(
                for: .nanoGpt,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }

        case .chutes:
            if let planText = resolvedPlanDisplayText(
                for: .chutes,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                addPlanSection(to: submenu, planText: planText)
            }

            if let daily = details.dailyUsage,
               let limit = details.limit {
                let used = Int(daily)
                let total = Int(limit)
                let percentage = total > 0 ? Int((Double(used) / Double(total)) * 100) : 0

                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Daily Requests: %d / %d (%.0f%% used)"), used, total, Double(percentage)))
                submenu.addItem(item)
            }

            let chutesMonthlyValue = resolvedChutesMonthlyValuePresentation(details: details)

            if let usedUSD = chutesMonthlyValue.usedUSD,
               let capUSD = chutesMonthlyValue.capUSD,
               let usedPercent = chutesMonthlyValue.usedPercent {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(
                    text: String(format: L("Monthly Value Used: $%.2f / $%.2f (%.0f%% used)"), usedUSD, capUSD, usedPercent)
                )
                submenu.addItem(item)
            } else if let capUSD = chutesMonthlyValue.capUSD {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(
                    text: String(format: L("Monthly Cap: $%.2f (5× subscription)"), capUSD)
                )
                submenu.addItem(item)
            }

            if let credits = details.creditsBalance {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: String(format: L("Credits Balance: $%.2f"), credits))
                submenu.addItem(item)
            }

            let overageItem = NSMenuItem()
            overageItem.view = createDisabledLabelView(text: L("Overage: PAYGO after cap"))
            submenu.addItem(overageItem)

        case .synthetic:
            if let fiveHour = details.fiveHourUsage {
                let rows = createUsageWindowRow(
                    label: L("5h"),
                    usagePercent: fiveHour,
                    resetDate: details.fiveHourReset,
                    windowHours: 5
                )
                rows.forEach { submenu.addItem($0) }
            }
            if let limit = details.limit, let remaining = details.limitRemaining {
                let item = NSMenuItem()
                item.view = createDisabledLabelView(
                    text: String(format: L("Limit: %.1f/%.1f"), remaining, limit),
                    icon: NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Limit")
                )
                submenu.addItem(item)
            }

            if let planText = resolvedPlanDisplayText(
                for: .synthetic,
                rawPlanName: details.planType,
                accountId: accountId,
                email: details.email
            ) {
                submenu.addItem(NSMenuItem.separator())
                addPlanSection(to: submenu, planText: planText)
            }
        }

        if let daily = details.dailyUsage {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Daily: $%.2f"), daily),
                icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: "Daily")
            )
            submenu.addItem(item)
        }

        if let weekly = details.weeklyUsage {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Weekly: $%.2f"), weekly),
                icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: L("Weekly"))
            )
            submenu.addItem(item)
        }

        if let monthly = details.monthlyUsage {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Monthly: $%.2f"), monthly),
                icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: L("Monthly"))
            )
            submenu.addItem(item)
        }

        if let remaining = details.remainingCredits {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Credits: $%.2f left"), remaining),
                icon: NSImage(systemSymbolName: "creditcard", accessibilityDescription: "Credits")
            )
            submenu.addItem(item)
        }

        if let limit = details.limit, let remaining = details.limitRemaining {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Limit: $%.2f / $%.2f"), remaining, limit),
                icon: NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Limit")
            )
            submenu.addItem(item)
        }

        if let period = details.resetPeriod {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: String(format: L("Resets: %@"), period),
                icon: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Reset")
            )
            submenu.addItem(item)
        }

        // Skip generic "Token From:" for providers that already render it in their case block above.
        // Providers with their own Account section: copilot, claude, codex, geminiCLI, antigravity
        let providersWithOwnAccountSection: Set<ProviderIdentifier> = [.copilot, .claude, .codex, .geminiCLI, .antigravity]
        if let authSource = details.authSource, !providersWithOwnAccountSection.contains(identifier) {
            createAccountInfoSection(items: [
                (sfSymbol: "key", text: String(format: L("Token From: %@"), authSource))
            ]).forEach { submenu.addItem($0) }
        }

        return submenu
    }

    private func addPlanSection(to submenu: NSMenu, planText: String) {
        let headerItem = NSMenuItem()
        headerItem.view = createDisabledLabelView(
            text: L("Plan"),
            font: NSFont.systemFont(ofSize: 11, weight: .bold)
        )
        submenu.addItem(headerItem)

        let item = NSMenuItem()
        item.view = createDisabledLabelView(
            text: planText,
            icon: NSImage(systemSymbolName: "crown", accessibilityDescription: "Plan")
        )
        submenu.addItem(item)
    }

    private func codexEmail(for accountId: String?) -> String? {
        guard let accountId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountId.isEmpty else {
            return nil
        }

        return TokenManager.shared.getOpenAIAccounts().first { account in
            account.accountId == accountId
        }?.email
    }

    private func resolvedChutesMonthlyValuePresentation(details: DetailedUsage) -> (usedUSD: Double?, capUSD: Double?, usedPercent: Double?) {
        let configuredPlan = SubscriptionSettingsManager.shared.getPlan(for: .chutes)
        let configuredCapUSD = configuredPlan.isSet
            ? configuredPlan.cost * ChutesProvider.monthlyValueMultiplier
            : nil
        let capUSD = configuredCapUSD ?? details.chutesMonthlyValueCapUSD
        let usedUSD = details.chutesMonthlyValueUsedUSD

        let usedPercent: Double?
        if let usedUSD, let capUSD, capUSD > 0 {
            usedPercent = min(max((usedUSD / capUSD) * 100.0, 0), 999)
        } else {
            usedPercent = details.chutesMonthlyValueUsedPercent
        }

        return (usedUSD, capUSD, usedPercent)
    }

    private func resolvedPlanDisplayText(
        for provider: ProviderIdentifier,
        rawPlanName: String?,
        accountId: String?,
        email: String?
    ) -> String? {
        let normalizedRawPlanName = normalizedPlanName(rawPlanName, for: provider)
        let subscriptionAccountId = resolvedSubscriptionAccountId(
            for: provider,
            accountId: accountId,
            email: email
        )
        let configuredPlan = SubscriptionSettingsManager.shared.getPlan(
            for: provider,
            accountId: subscriptionAccountId
        )

        guard configuredPlan.isSet else {
            return normalizedRawPlanName
        }

        let amountText = String(format: "$%.2f/m", configuredPlan.cost)
        if let normalizedRawPlanName {
            return "\(normalizedRawPlanName) (\(amountText))"
        }

        switch configuredPlan {
        case .preset(let name, _):
            return "\(name) (\(amountText))"
        case .custom:
            return "\(L("Custom")) (\(amountText))"
        case .none:
            return nil
        }
    }

    private func resolvedSubscriptionAccountId(
        for provider: ProviderIdentifier,
        accountId: String?,
        email: String?
    ) -> String? {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let trimmedEmail, !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        let trimmedAccountId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAccountId, !trimmedAccountId.isEmpty {
            return trimmedAccountId
        }

        debugLog("resolvedSubscriptionAccountId: no stable account identifier for \(provider.rawValue)")
        return nil
    }

    private func normalizedPlanName(_ rawPlanName: String?, for provider: ProviderIdentifier) -> String? {
        guard let rawPlanName = rawPlanName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlanName.isEmpty else {
            return nil
        }

        if provider == .copilot {
            switch rawPlanName.lowercased() {
            case "individual_pro":
                return "Pro"
            case "individual_free":
                return "Free"
            case "business":
                return "Business"
            case "enterprise":
                return "Enterprise"
            default:
                break
            }
        }

        let normalized = rawPlanName
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        if normalized.lowercased() == normalized {
            return normalized.capitalized
        }
        return normalized
    }

    private func addGroupedModelUsageSection(
        to submenu: NSMenu,
        modelBreakdown: [String: Double],
        modelResetTimes: [String: Date]?,
        paceWindowHours: Int,
        debugContext: String
    ) {
        let groupedUsageWindows = ModelUsageGrouper.groupedUsageWindows(
            modelBreakdown: modelBreakdown,
            modelResetTimes: modelResetTimes
        )

        debugLog(
            "\(debugContext): grouped \(modelBreakdown.count) model bucket(s) into \(groupedUsageWindows.count) group(s)"
        )

        let didGroup = groupedUsageWindows.count < modelBreakdown.count
        let dividerCount = didGroup ? max(0, groupedUsageWindows.count - 1) : 0
        debugLog("\(debugContext): adding \(dividerCount) divider(s) between model groups")

        let shouldAddWindowInfoDivider = groupedUsageWindows.count == 1
            && (groupedUsageWindows.first?.models.count ?? 0) > 1
            && groupedUsageWindows.first?.resetDate != nil
        if shouldAddWindowInfoDivider {
            debugLog("\(debugContext): adding divider between model list and pace/reset info")
        }

        // Keep one model per row to avoid long wrapped labels while still sharing reset/pace
        // for groups that have the same usage and quota reset window.
        for (groupIndex, grouped) in groupedUsageWindows.enumerated() {
            for model in grouped.models {
                let usageItem = NSMenuItem()
                usageItem.view = createDisabledLabelView(
                    text: String(format: L("%@: %.0f%% used"), model, grouped.usedPercent)
                )
                submenu.addItem(usageItem)
            }

            if let resetDate = grouped.resetDate {
                if groupIndex == 0, shouldAddWindowInfoDivider {
                    submenu.addItem(NSMenuItem.separator())
                }

                let paceInfo = calculatePace(usage: grouped.usedPercent, resetTime: resetDate, windowHours: paceWindowHours)
                let paceItem = NSMenuItem()
                paceItem.view = createPaceView(paceInfo: paceInfo)
                submenu.addItem(paceItem)

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
                formatter.timeZone = TimeZone.current

                let resetItem = NSMenuItem()
                resetItem.view = createDisabledLabelView(
                    text: String(format: L("Resets: %@"), formatter.string(from: resetDate)),
                    indent: 0,
                    textColor: .secondaryLabelColor
                )
                submenu.addItem(resetItem)
                debugLog("\(debugContext): reset row tone aligned with pace text")
                debugLog("\(debugContext): group \(groupIndex) order applied -> pace row above reset row")
            }

            if groupIndex < groupedUsageWindows.count - 1 {
                submenu.addItem(NSMenuItem.separator())
            }
        }
    }

    func createGeminiAccountSubmenu(_ account: GeminiAccountQuota) -> NSMenu {
        let submenu = NSMenu()

        addGroupedModelUsageSection(
            to: submenu,
            modelBreakdown: account.modelBreakdown,
            modelResetTimes: account.modelResetTimes,
            paceWindowHours: 24,
            debugContext: "createGeminiAccountSubmenu(\(account.email))"
        )

        var accountItems: [(sfSymbol: String, text: String)] = [
            (sfSymbol: "person.circle", text: account.email),
            (sfSymbol: "key", text: String(format: L("Token From: %@"), account.authSource))
        ]
        if let accountId = account.accountId, !accountId.isEmpty {
            accountItems.insert((sfSymbol: "number.circle", text: String(format: L("Account ID: %@"), accountId)), at: 1)
        }
        createAccountInfoSection(items: accountItems).forEach { submenu.addItem($0) }

        return submenu
    }

    func createCopilotHistorySubmenu() -> NSMenu {
        debugLog("createCopilotHistorySubmenu: started")
        let submenu = NSMenu()
        debugLog("createCopilotHistorySubmenu: calling getHistoryUIState")
        let state = getHistoryUIState()
        debugLog("createCopilotHistorySubmenu: getHistoryUIState completed")

        if state.hasNoData {
            debugLog("createCopilotHistorySubmenu: hasNoData=true, returning early")
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: L("No data"),
                icon: NSImage(systemSymbolName: "tray", accessibilityDescription: L("No data"))
            )
            submenu.addItem(item)
            return submenu
        }
        debugLog("createCopilotHistorySubmenu: hasNoData=false, continuing")

        if state.isStale {
            debugLog("createCopilotHistorySubmenu: data is stale")
            let staleItem = NSMenuItem()
            staleItem.view = createDisabledLabelView(
                text: L("Data is stale"),
                icon: NSImage(systemSymbolName: "clock.badge.exclamationmark", accessibilityDescription: L("Data is stale"))
            )
            submenu.addItem(staleItem)
            debugLog("createCopilotHistorySubmenu: stale item added")
        }

        if let history = state.history {
            debugLog("createCopilotHistorySubmenu: history exists, processing \(history.recentDays.count) days")

            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let today = utcCalendar.startOfDay(for: Date())

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 0

            for day in history.recentDays {
                let dayStart = utcCalendar.startOfDay(for: day.date)
                let isToday = dayStart == today
                let dateStr = SharedDateFormatters.monthDay.string(from: day.date)
                let billedAmount = day.billedAmount
                let overageReq = Int(day.billedRequests)
                let label: String
                if isToday {
                    label = String(format: "%@ (Today): %d overage ($%.2f)", dateStr, overageReq, billedAmount)
                } else {
                    label = String(format: "%@: %d overage ($%.2f)", dateStr, overageReq, billedAmount)
                }

                let item = NSMenuItem()
                item.view = createDisabledLabelView(text: label, monospaced: true)
                submenu.addItem(item)
            }
            debugLog("createCopilotHistorySubmenu: all history items added")
        } else {
            debugLog("createCopilotHistorySubmenu: no history")
        }

         debugLog("createCopilotHistorySubmenu: completed successfully")
         return submenu
    }

    enum PaceStatus {
        case usedUp
        case onTrack
        case slightlyFast
        case tooFast

        var color: NSColor {
            switch self {
            case .usedUp: return .systemRed
            case .onTrack: return .systemGreen
            case .slightlyFast: return .systemOrange
            case .tooFast: return .systemRed
            }
        }
    }

    struct PaceInfo {
        let elapsedRatio: Double
        let usageRatio: Double
        let predictedFinalUsage: Double
        let remainingSeconds: TimeInterval
        let isExhausted: Bool
        let elapsedSeconds: TimeInterval
        let totalSeconds: TimeInterval

        var status: PaceStatus {
            if isExhausted {
                return .usedUp
            }
            if usageRatio <= elapsedRatio {
                return .onTrack
            } else if predictedFinalUsage <= 130 {
                return .slightlyFast
            } else {
                return .tooFast
            }
        }

        private var paceUnitSuffix: String {
            // 5d+ => per day, otherwise per hour.
            if totalSeconds >= (5.0 * 24.0 * 3600.0) {
                return "d"
            }
            return "h"
        }

        var paceRateText: String {
            guard totalSeconds > 0 else { return L("Unavailable") }

            let unitSeconds: Double = paceUnitSuffix == "d" ? 86400.0 : 3600.0
            let totalUnits = totalSeconds / unitSeconds
            guard totalUnits > 0 else { return L("Unavailable") }

            let elapsedUnitsRaw = elapsedSeconds / unitSeconds
            let minElapsedUnits = max(0.0001, totalUnits * 0.01)
            let elapsedUnits = max(elapsedUnitsRaw, minElapsedUnits)

            let usagePercent = usageRatio * 100.0
            let pacePercentPerUnit = usagePercent / elapsedUnits
            guard pacePercentPerUnit.isFinite else { return L("Unavailable") }

            let clamped = min(999.9, max(0.0, pacePercentPerUnit))
            return String(format: "%.1f%%/%@", clamped, paceUnitSuffix)
        }

        var predictText: String {
            return String(format: "%.0f%%", predictedFinalUsage)
        }
    }

    private func formatRemainingTime(seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60
        let days = totalHours / 24
        let hours = totalHours % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h left"
        }
        if totalHours > 0 {
            return "\(totalHours)h left"
        }
        if totalMinutes == 0 {
            return L("less than 1m left")
        }
        return "\(minutes)m left"
    }

    func calculatePace(usage: Double, resetTime: Date, windowHours: Int) -> PaceInfo {
        let windowSeconds = Double(windowHours) * 3600.0
        let now = Date()
        let remainingSeconds = resetTime.timeIntervalSince(now)
        let rawElapsedSeconds = windowSeconds - remainingSeconds
        let boundedElapsedSeconds = max(0, min(windowSeconds, rawElapsedSeconds))

        // Rolling windows (especially weekly) can show extreme spikes right after usage starts.
        // Use a stability floor so Speed/Predict are less noisy in very early phases.
        let minElapsedRatioForForecast: Double
        if windowHours >= 168 {
            minElapsedRatioForForecast = 0.5
        } else if windowHours >= 24 {
            minElapsedRatioForForecast = 0.25
        } else {
            minElapsedRatioForForecast = 0.05
        }

        let minElapsedSeconds = windowSeconds * minElapsedRatioForForecast
        let elapsedSeconds = max(boundedElapsedSeconds, minElapsedSeconds)
        let elapsedRatio = max(0, min(1, elapsedSeconds / windowSeconds))
        let usageRatio = usage / 100.0
        let isExhausted = usage >= 100 && remainingSeconds > 0

        let predictedFinalUsage: Double
        if elapsedRatio > 0.01 {
            predictedFinalUsage = min(999, (usageRatio / elapsedRatio) * 100.0)
        } else {
            predictedFinalUsage = usage
        }

        return PaceInfo(
            elapsedRatio: elapsedRatio,
            usageRatio: usageRatio,
            predictedFinalUsage: predictedFinalUsage,
            remainingSeconds: remainingSeconds,
            isExhausted: isExhausted,
            elapsedSeconds: elapsedSeconds,
            totalSeconds: windowSeconds
        )
    }

    func calculateMonthlyPace(usagePercent: Double, resetDate: Date) -> PaceInfo {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") {
            calendar.timeZone = utc
        }

        let remainingSeconds = resetDate.timeIntervalSince(now)
        let isExhausted = usagePercent >= 100 && remainingSeconds > 0

        guard let billingStart = calendar.date(byAdding: DateComponents(month: -1), to: resetDate) else {
            return PaceInfo(
                elapsedRatio: 0,
                usageRatio: usagePercent / 100.0,
                predictedFinalUsage: usagePercent,
                remainingSeconds: remainingSeconds,
                isExhausted: isExhausted,
                elapsedSeconds: 0,
                totalSeconds: 0
            )
        }

        let totalSeconds = max(0, resetDate.timeIntervalSince(billingStart))
        let elapsedSeconds = max(0, min(totalSeconds, now.timeIntervalSince(billingStart)))

        guard totalSeconds > 0 else {
            return PaceInfo(
                elapsedRatio: 0,
                usageRatio: usagePercent / 100.0,
                predictedFinalUsage: usagePercent,
                remainingSeconds: remainingSeconds,
                isExhausted: isExhausted,
                elapsedSeconds: elapsedSeconds,
                totalSeconds: totalSeconds
            )
        }

        let elapsedRatio = max(0, min(1, elapsedSeconds / totalSeconds))
        let usageRatio = usagePercent / 100.0

        let predictedFinalUsage: Double
        if elapsedRatio > 0.01 {
            predictedFinalUsage = min(999, (usageRatio / elapsedRatio) * 100.0)
        } else {
            predictedFinalUsage = usagePercent
        }

        return PaceInfo(
            elapsedRatio: elapsedRatio,
            usageRatio: usageRatio,
            predictedFinalUsage: predictedFinalUsage,
            remainingSeconds: remainingSeconds,
            isExhausted: isExhausted,
            elapsedSeconds: elapsedSeconds,
            totalSeconds: totalSeconds
        )
    }

    func createPaceView(paceInfo: PaceInfo) -> NSView {
        let menuWidth: CGFloat = MenuDesignToken.Dimension.menuWidth
        let itemHeight: CGFloat = MenuDesignToken.Dimension.itemHeight
        let leadingOffset: CGFloat = MenuDesignToken.Spacing.leadingOffset
        let trailingMargin: CGFloat = MenuDesignToken.Spacing.trailingMargin
        let statusDotSize: CGFloat = MenuDesignToken.Dimension.statusDotSize
        let fontSize: CGFloat = MenuDesignToken.Dimension.fontSize

        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: itemHeight))

        let paceText = paceInfo.paceRateText
        debugLog("createPaceView: pace label computed: \(paceText)")
        let leftTextField = NSTextField(labelWithString: String(format: L("Speed: %@"), paceText))
        leftTextField.font = NSFont.systemFont(ofSize: fontSize)
        leftTextField.textColor = .secondaryLabelColor
        leftTextField.lineBreakMode = .byTruncatingTail
        leftTextField.maximumNumberOfLines = 1
        leftTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if paceInfo.isExhausted {
            leftTextField.stringValue = ""
            leftTextField.isHidden = true
            debugLog("createPaceView: hiding pace label for exhausted usage")
        }
        leftTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftTextField)
        NSLayoutConstraint.activate([
            leftTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingOffset),
            leftTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let hasTooFast = paceInfo.status == .tooFast
        var rightEdge = menuWidth - trailingMargin
        let emphasisColor = paceInfo.status.color

        if hasTooFast {
            let statusIconSize = MenuDesignToken.Dimension.paceStatusIconSize
            let statusIconY = (itemHeight - statusIconSize) / 2
            let statusIconView = NSImageView(
                frame: NSRect(
                    x: rightEdge - statusIconSize,
                    y: statusIconY,
                    width: statusIconSize,
                    height: statusIconSize
                )
            )
            if let statusIcon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Too fast") {
                let config = NSImage.SymbolConfiguration(pointSize: statusIconSize, weight: .regular)
                statusIconView.image = statusIcon.withSymbolConfiguration(config)
                statusIconView.contentTintColor = emphasisColor
            }
            view.addSubview(statusIconView)
            rightEdge -= statusIconSize + MenuDesignToken.Spacing.trailingMargin - MenuDesignToken.Dimension.statusDotSize
        }

        let dotY: CGFloat = (itemHeight - statusDotSize) / 2
        let dotImageView = NSImageView(frame: NSRect(x: rightEdge - statusDotSize, y: dotY, width: statusDotSize, height: statusDotSize))
        if let dotImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Status") {
            let config = NSImage.SymbolConfiguration(pointSize: statusDotSize, weight: .regular)
            dotImageView.image = dotImage.withSymbolConfiguration(config)
            dotImageView.contentTintColor = emphasisColor
        }
        view.addSubview(dotImageView)
        let dotSpacing = MenuDesignToken.Spacing.trailingMargin - MenuDesignToken.Dimension.statusDotSize
        rightEdge -= (statusDotSize + dotSpacing)

        let rightTextField = NSTextField(labelWithString: "")
        let rightAttributedString = NSMutableAttributedString()
        let exhaustedStatusTextField = NSTextField(labelWithString: "")
        if paceInfo.isExhausted {
            let waitText = formatRemainingTime(seconds: paceInfo.remainingSeconds)
            debugLog("createPaceView: usage exhausted, showing wait message \(waitText)")
            let exhaustedStatusAttributedString = NSMutableAttributedString()
            exhaustedStatusAttributedString.append(NSAttributedString(
                string: L("Status: "),
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            exhaustedStatusAttributedString.append(NSAttributedString(
                string: L("Used Up"),
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: emphasisColor]
            ))
            exhaustedStatusTextField.attributedStringValue = exhaustedStatusAttributedString
            exhaustedStatusTextField.isBezeled = false
            exhaustedStatusTextField.isEditable = false
            exhaustedStatusTextField.isSelectable = false
            exhaustedStatusTextField.drawsBackground = false
            exhaustedStatusTextField.lineBreakMode = .byTruncatingTail
            exhaustedStatusTextField.maximumNumberOfLines = 1
            exhaustedStatusTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            exhaustedStatusTextField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(exhaustedStatusTextField)

            rightAttributedString.append(NSAttributedString(
                string: L("Wait "),
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            rightAttributedString.append(NSAttributedString(
                string: waitText,
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: emphasisColor]
            ))
            rightTextField.isHidden = false
        } else {
            debugLog("createPaceView: predict label computed: \(paceInfo.predictText)")
            let isPredictWarning = paceInfo.status == .slightlyFast || paceInfo.status == .tooFast
            let predictValueColor: NSColor = isPredictWarning ? emphasisColor : .secondaryLabelColor
            debugLog("createPaceView: predict color mode = \(isPredictWarning ? "warning" : "default"), status = \(paceInfo.status)")
            rightAttributedString.append(NSAttributedString(
                string: L("Predict: "),
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ))
            rightAttributedString.append(NSAttributedString(
                string: paceInfo.predictText,
                attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: predictValueColor]
            ))
            rightTextField.isHidden = false
        }
        rightTextField.attributedStringValue = rightAttributedString
        rightTextField.isBezeled = false
        rightTextField.isEditable = false
        rightTextField.isSelectable = false
        rightTextField.drawsBackground = false
        rightTextField.lineBreakMode = .byTruncatingTail
        rightTextField.maximumNumberOfLines = 1
        rightTextField.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightTextField.setContentHuggingPriority(.required, for: .horizontal)
        rightTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightTextField)
        if paceInfo.isExhausted {
            rightTextField.alignment = .right
            NSLayoutConstraint.activate([
                exhaustedStatusTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingOffset),
                exhaustedStatusTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                exhaustedStatusTextField.trailingAnchor.constraint(lessThanOrEqualTo: rightTextField.leadingAnchor, constant: -dotSpacing),
                rightTextField.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: rightEdge),
                rightTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            debugLog("createPaceView: exhausted row split layout (status left, wait right)")
        } else {
            rightTextField.alignment = .right
            NSLayoutConstraint.activate([
                rightTextField.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: rightEdge),
                rightTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                leftTextField.trailingAnchor.constraint(lessThanOrEqualTo: rightTextField.leadingAnchor, constant: -dotSpacing)
            ])
        }

        return view
    }

    private func usageColorForSummary(usagePercent: Double, paceInfo: PaceInfo?) -> NSColor {
        if let paceInfo {
            return paceInfo.status.color
        }
        if usagePercent >= 100 {
            return .systemRed
        }
        if usagePercent >= 80 {
            return .systemOrange
        }
        return .systemGreen
    }

    func createUsageSummaryView(label: String, usagePercent: Double, valueColor: NSColor) -> NSView {
        let menuWidth: CGFloat = MenuDesignToken.Dimension.menuWidth
        let itemHeight: CGFloat = MenuDesignToken.Dimension.itemHeight
        let leadingOffset: CGFloat = MenuDesignToken.Spacing.leadingOffset
        let trailingMargin: CGFloat = MenuDesignToken.Spacing.trailingMargin
        let minimumGap: CGFloat = MenuDesignToken.Spacing.submenuIndent
        let headerFontSize: CGFloat = 11

        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: itemHeight))

        let leftTextField = NSTextField(labelWithString: label)
        leftTextField.font = NSFont.systemFont(ofSize: headerFontSize, weight: .bold)
        leftTextField.textColor = .secondaryLabelColor
        leftTextField.lineBreakMode = .byTruncatingTail
        leftTextField.maximumNumberOfLines = 1
        leftTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftTextField)

        let rightTextField = NSTextField(labelWithString: "")
        let rightAttributedString = NSMutableAttributedString()
        rightAttributedString.append(NSAttributedString(
            string: L("Used: "),
            attributes: [.font: NSFont.boldSystemFont(ofSize: headerFontSize), .foregroundColor: NSColor.disabledControlTextColor]
        ))
        rightAttributedString.append(NSAttributedString(
            string: UsagePercentDisplayFormatter.string(from: usagePercent),
            attributes: [.font: NSFont.boldSystemFont(ofSize: headerFontSize), .foregroundColor: valueColor]
        ))
        rightTextField.attributedStringValue = rightAttributedString
        rightTextField.alignment = .right
        rightTextField.lineBreakMode = .byTruncatingTail
        rightTextField.maximumNumberOfLines = 1
        rightTextField.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightTextField.setContentHuggingPriority(.required, for: .horizontal)
        rightTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightTextField)

        NSLayoutConstraint.activate([
            leftTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingOffset),
            leftTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            rightTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -trailingMargin),
            rightTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            leftTextField.trailingAnchor.constraint(lessThanOrEqualTo: rightTextField.leadingAnchor, constant: -minimumGap)
        ])

        debugLog("createUsageSummaryView: \(label) -> Used \(Int(usagePercent.rounded()))%")
        return view
    }

    /// Creates unified usage window display with optional pace indicator and reset time.
    /// Returns array of NSMenuItems: [usage row, pace row (optional), reset row (optional)]
    func createUsageWindowRow(
        label: String,
        usagePercent: Double,
        resetDate: Date? = nil,
        windowHours: Int? = nil,
        isMonthly: Bool = false
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let paceInfoForColor: PaceInfo?
        if let resetDate = resetDate {
            if isMonthly {
                paceInfoForColor = calculateMonthlyPace(usagePercent: usagePercent, resetDate: resetDate)
            } else if let windowHours = windowHours {
                paceInfoForColor = calculatePace(usage: usagePercent, resetTime: resetDate, windowHours: windowHours)
            } else {
                paceInfoForColor = nil
            }
        } else {
            paceInfoForColor = nil
        }

        let usageColor = usageColorForSummary(usagePercent: usagePercent, paceInfo: paceInfoForColor)
        debugLog("createUsageWindowRow: usage row \(label) = \(usagePercent)%")

        let usageItem = NSMenuItem()
        usageItem.view = createUsageSummaryView(label: label, usagePercent: usagePercent, valueColor: usageColor)
        items.append(usageItem)

        guard let resetDate = resetDate else {
            return items
        }

        guard let paceInfo = paceInfoForColor else {
            return items
        }

        let paceItem = NSMenuItem()
        paceItem.view = createPaceView(paceInfo: paceInfo)
        items.append(paceItem)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        formatter.timeZone = TimeZone.current
        let resetItem = NSMenuItem()
        resetItem.view = createDisabledLabelView(
            text: String(format: L("Resets: %@"), formatter.string(from: resetDate)),
            indent: 0,
            textColor: .secondaryLabelColor
        )
        items.append(resetItem)
        debugLog("createUsageWindowRow: reset row tone aligned with pace text for \(label)")
        debugLog("createUsageWindowRow: order applied for \(label) -> usage, pace, reset")

        return items
    }

    /// Creates a "used/total" display row with optional unit prefix.
    /// Example: "Tokens: 12,345 / 100,000", "Credits: $3.50 / $10.00"
    func createLimitRow(label: String, used: Double, total: Double, unitPrefix: String = "") -> NSMenuItem {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 0

        let formattedUsed = numberFormatter.string(from: NSNumber(value: used)) ?? "\(Int(used))"
        let formattedTotal = numberFormatter.string(from: NSNumber(value: total)) ?? "\(Int(total))"

        let item = NSMenuItem()
        item.view = createDisabledLabelView(
            text: "\(label): \(unitPrefix)\(formattedUsed) / \(unitPrefix)\(formattedTotal)"
        )
        return item
    }

    /// Creates unified account info section with SF Symbol icons.
    /// Returns [separator, header, item1, item2, ...]. Enables multiline for "Token From:" items.
    func createAccountInfoSection(items: [(sfSymbol: String, text: String)]) -> [NSMenuItem] {
        var menuItems: [NSMenuItem] = []
        menuItems.append(NSMenuItem.separator())

        let headerItem = NSMenuItem()
        headerItem.view = createDisabledLabelView(
            text: L("Account"),
            font: NSFont.systemFont(ofSize: 11, weight: .bold)
        )
        menuItems.append(headerItem)

        for item in items {
            let menuItem = NSMenuItem()
            let needsMultiline = item.sfSymbol == "key"
            let displayText: String
            switch item.sfSymbol {
            case "key", "number.circle":
                displayText = PrivacyRedactor.displayLabeledValue(item.text)
            case "person.circle":
                displayText = item.text.contains(": ")
                    ? PrivacyRedactor.displayLabeledValue(item.text)
                    : PrivacyRedactor.display(item.text)
            default:
                displayText = item.text
            }
            menuItem.view = createDisabledLabelView(
                text: displayText,
                icon: NSImage(systemSymbolName: item.sfSymbol, accessibilityDescription: nil),
                multiline: needsMultiline
            )
            menuItems.append(menuItem)
        }

        return menuItems
    }

}
