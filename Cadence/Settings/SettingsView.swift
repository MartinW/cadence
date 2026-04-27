import SwiftUI

/// Onboarding + ongoing config — paste keys, save them in Keychain.
///
/// On first run we surface this directly (RootView routes here when
/// `isConfigured` is false). After that it's reachable from the prompt list
/// toolbar's gear icon.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// True when launched from the unconfigured root view; controls which
    /// confirmation copy + button label we show.
    var isFirstRun: Bool = false

    @State private var showSaved = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            if isFirstRun {
                Section {
                    Text("Paste your Langfuse and OpenRouter keys to get started.")
                        .font(.callout)
                    Text("Keys are stored in iOS Keychain on this device only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Langfuse") {
                TextField("Public key (pk-lf-…)", text: $settings.langfusePublicKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Secret key (sk-lf-…)", text: $settings.langfuseSecretKey)
                TextField("Host", text: $settings.langfuseHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            Section("OpenRouter") {
                SecureField("API key (sk-or-…)", text: $settings.openrouterApiKey)
                Text("Used for prompt reasoning + audio synthesis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    settings.save()
                    showSaved = true
                    if !isFirstRun {
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(isFirstRun ? "Continue" : "Save")
                            .bold()
                        Spacer()
                    }
                }
                .disabled(!settings.isConfigured)
            }
        }
        .navigationTitle(isFirstRun ? "Welcome to Cadence" : "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved", isPresented: $showSaved) {
            Button("OK") {
                showSaved = false
            }
        } message: {
            Text("Credentials stored in Keychain.")
        }
    }
}
