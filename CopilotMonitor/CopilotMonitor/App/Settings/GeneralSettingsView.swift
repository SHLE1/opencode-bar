import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    @State private var cliInstalled = CLIService.isInstalled
    @State private var cliActionMessage: String?
    @State private var showingCLIAlert = false

    var body: some View {
        Form {
            // MARK: - Refresh & Prediction

            Section {
                Picker("Auto Refresh Period", selection: $prefs.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.title).tag(interval)
                    }
                }

                Picker("Prediction Period", selection: $prefs.predictionPeriod) {
                    ForEach(PredictionPeriod.allCases, id: \.self) { period in
                        Text(period.title).tag(period)
                    }
                }
            }

            // MARK: - Launch at Login

            Section {
                Toggle("Launch at Login", isOn: $prefs.launchAtLogin)
            }

            // MARK: - CLI

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command Line Tool")
                            .font(.body)
                        Text(cliInstalled
                             ? "Installed at \(CLIService.installPath)"
                             : "Not installed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if cliInstalled {
                        Button("Uninstall") {
                            performCLIAction(install: false)
                        }
                    } else {
                        Button("Install") {
                            performCLIAction(install: true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("CLI", isPresented: $showingCLIAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cliActionMessage ?? "")
        }
    }

    // MARK: - Helpers

    private func performCLIAction(install: Bool) {
        let error: String?
        if install {
            error = CLIService.install()
        } else {
            error = CLIService.uninstall()
        }

        cliInstalled = CLIService.isInstalled

        if let error = error {
            cliActionMessage = error
            showingCLIAlert = true
        } else {
            let verb = install ? "installed" : "uninstalled"
            cliActionMessage = "CLI \(verb) successfully."
            showingCLIAlert = true
        }
    }
}
