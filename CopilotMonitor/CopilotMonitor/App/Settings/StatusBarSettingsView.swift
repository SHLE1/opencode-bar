import SwiftUI

struct StatusBarSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            // MARK: - Enabled Providers

            Section("Enabled Providers") {
                ForEach(ProviderIdentifier.allCases, id: \.self) { identifier in
                    Toggle(identifier.displayName, isOn: providerEnabledBinding(for: identifier))
                }
            }

            // MARK: - Additional Cost Items

            Section("Additional Cost Items") {
                Toggle("GitHub Copilot Add-on", isOn: $prefs.copilotAddOnEnabled)
            }

            // MARK: - Multi-Provider Bar

            Section("Multi-Provider Bar Providers") {
                ForEach(ProviderIdentifier.allCases, id: \.self) { identifier in
                    Toggle(identifier.displayName, isOn: multiProviderBinding(for: identifier))
                }
            }

            // MARK: - Options

            Section("Options") {
                Toggle("Critical Badge", isOn: $prefs.criticalBadge)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings

    private func providerEnabledBinding(for identifier: ProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { prefs.isProviderEnabled(identifier) },
            set: { newValue in prefs.setProviderEnabled(identifier, enabled: newValue) }
        )
    }

    private func multiProviderBinding(for identifier: ProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { prefs.multiProviderProviders.contains(identifier) },
            set: { included in
                if included {
                    prefs.multiProviderProviders.insert(identifier)
                } else {
                    prefs.multiProviderProviders.remove(identifier)
                }
            }
        )
    }
}
