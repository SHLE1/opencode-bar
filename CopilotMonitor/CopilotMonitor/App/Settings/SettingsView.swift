import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            StatusBarSettingsView()
                .tabItem {
                    Label("Status Bar", systemImage: "menubar.rectangle")
                }

            SubscriptionSettingsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "creditcard")
                }
        }
        .frame(width: 480, height: 400)
    }
}
