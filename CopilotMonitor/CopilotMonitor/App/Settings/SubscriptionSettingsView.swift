import SwiftUI

/// Manages subscription cost settings for all quota-based providers.
/// Pay-as-you-go providers (OpenRouter, OpenCode Zen, etc.) are intentionally excluded.
struct SubscriptionSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var rows: [SubscriptionRow] = []
    @State private var totalCost: Double = 0

    /// Providers that support subscription presets (quota-based only).
    private static let subscribableProviders: [ProviderIdentifier] = {
        ProviderIdentifier.allCases.filter { !ProviderSubscriptionPresets.presets(for: $0).isEmpty }
    }()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            HStack {
                Text("Monthly Total")
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.2f/m", totalCost))
                    .font(.system(.headline, design: .monospaced))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // MARK: - Subscription List

            List {
                ForEach($rows) { $row in
                    SubscriptionRowView(row: $row, onChanged: recalculate)
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
    }

    // MARK: - Data Loading

    private func reload() {
        let manager = SubscriptionSettingsManager.shared
        let allSavedKeys = Set(manager.getAllSubscriptionKeys())

        var seen = Set<String>()
        var result: [SubscriptionRow] = []

        // 1) Enumerate subscribable providers — one row per provider (or per account if saved)
        for provider in Self.subscribableProviders {
            let baseKey = manager.subscriptionKey(for: provider)

            // Collect all saved keys that belong to this provider
            let providerKeys = allSavedKeys.filter { keyBelongsToProvider($0, provider: provider) }

            if providerKeys.isEmpty {
                // No saved subscription yet — show a single row for the provider
                let plan = manager.getPlan(forKey: baseKey)
                result.append(SubscriptionRow(
                    key: baseKey,
                    provider: provider,
                    plan: plan,
                    presets: ProviderSubscriptionPresets.presets(for: provider)
                ))
                seen.insert(baseKey)
            } else {
                for key in providerKeys.sorted() {
                    let plan = manager.getPlan(forKey: key)
                    result.append(SubscriptionRow(
                        key: key,
                        provider: provider,
                        plan: plan,
                        presets: ProviderSubscriptionPresets.presets(for: provider)
                    ))
                    seen.insert(key)
                }
            }
        }

        // 2) Orphaned keys (saved but provider not in subscribable list or account changed)
        for key in allSavedKeys.sorted() where !seen.contains(key) {
            let provider = providerFromKey(key)
            let presets = provider.map { ProviderSubscriptionPresets.presets(for: $0) } ?? []
            // Skip orphaned keys for pay-as-you-go providers
            if let prov = provider, ProviderSubscriptionPresets.presets(for: prov).isEmpty {
                continue
            }
            let plan = manager.getPlan(forKey: key)
            result.append(SubscriptionRow(
                key: key,
                provider: provider,
                plan: plan,
                presets: presets
            ))
        }

        rows = result
        recalculate()
    }

    private func recalculate() {
        // Persist all current row plans and recompute total
        let manager = SubscriptionSettingsManager.shared
        var sum: Double = 0
        for row in rows {
            manager.setPlan(row.plan, forKey: row.key)
            sum += row.plan.cost
        }
        totalCost = sum
        NotificationCenter.default.post(name: AppPreferences.subscriptionDidChange, object: nil)
    }

    // MARK: - Helpers

    private func keyBelongsToProvider(_ key: String, provider: ProviderIdentifier) -> Bool {
        return key == provider.rawValue || key.hasPrefix("\(provider.rawValue).")
    }

    private func providerFromKey(_ key: String) -> ProviderIdentifier? {
        let prefix = key.split(separator: ".", maxSplits: 1).first.map(String.init) ?? key
        return ProviderIdentifier(rawValue: prefix)
    }
}

// MARK: - Row Model

struct SubscriptionRow: Identifiable {
    let id: String // same as key
    let key: String
    let provider: ProviderIdentifier?
    var plan: SubscriptionPlan
    let presets: [SubscriptionPreset]

    init(key: String, provider: ProviderIdentifier?, plan: SubscriptionPlan, presets: [SubscriptionPreset]) {
        self.id = key
        self.key = key
        self.provider = provider
        self.plan = plan
        self.presets = presets
    }

    var displayName: String {
        guard let provider = provider else { return key }
        let base = provider.displayName
        // If key has an account suffix, show it
        let providerRaw = provider.rawValue
        if key.count > providerRaw.count + 1 && key.hasPrefix(providerRaw + ".") {
            let account = String(key.dropFirst(providerRaw.count + 1))
            return "\(base) (\(account))"
        }
        return base
    }
}

// MARK: - Row View

private struct SubscriptionRowView: View {
    @Binding var row: SubscriptionRow
    var onChanged: () -> Void

    @State private var customAmountText: String = ""
    @State private var showCustomField: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.displayName)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text(row.plan.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                // None button
                planButton(label: "None", selected: isNone) {
                    row.plan = .none
                    showCustomField = false
                    onChanged()
                }

                // Preset buttons — use cost for comparison (handles duplicate names)
                ForEach(Array(row.presets.enumerated()), id: \.offset) { _, preset in
                    let label = "\(preset.name) $\(Int(preset.cost))"
                    let isSelected = isPresetSelected(preset)
                    planButton(label: label, selected: isSelected) {
                        row.plan = .preset(preset.name, preset.cost)
                        showCustomField = false
                        onChanged()
                    }
                }

                // Custom button
                planButton(label: "Custom", selected: isCustom) {
                    showCustomField = true
                    if case .custom(let amount) = row.plan {
                        customAmountText = String(format: "%.0f", amount)
                    } else {
                        customAmountText = ""
                    }
                }

                if showCustomField {
                    TextField("$/m", text: $customAmountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit {
                            applyCustomAmount()
                        }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if case .custom = row.plan {
                showCustomField = true
                customAmountText = String(format: "%.0f", row.plan.cost)
            }
        }
    }

    // MARK: - State Helpers

    private var isNone: Bool {
        if case .none = row.plan { return true }
        return false
    }

    private var isCustom: Bool {
        if case .custom = row.plan { return true }
        return false
    }

    private func isPresetSelected(_ preset: SubscriptionPreset) -> Bool {
        if case .preset(_, let cost) = row.plan {
            return abs(cost - preset.cost) < 0.01
        }
        return false
    }

    private func applyCustomAmount() {
        guard let amount = Double(customAmountText), amount > 0 else {
            row.plan = .none
            onChanged()
            return
        }
        row.plan = .custom(amount)
        onChanged()
    }

    // MARK: - Button Helper

    private func planButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
