import Foundation
import Observation

/// Live model of the user's saved credentials.
///
/// Reads from Keychain on init, writes back on `save()`. Bound directly into
/// the SettingsView via `@Bindable`. The single source of truth in the app —
/// any view that needs Langfuse or OpenRouter access reads via Environment.
@MainActor
@Observable
final class SettingsStore {
    var langfusePublicKey: String
    var langfuseSecretKey: String
    var langfuseHost: String
    var openrouterApiKey: String

    init() {
        self.langfusePublicKey = SecretsStore.read("LANGFUSE_PUBLIC_KEY") ?? ""
        self.langfuseSecretKey = SecretsStore.read("LANGFUSE_SECRET_KEY") ?? ""
        self.langfuseHost = SecretsStore.read("LANGFUSE_HOST") ?? "https://cloud.langfuse.com"
        self.openrouterApiKey = SecretsStore.read("OPENROUTER_API_KEY") ?? ""
    }

    /// True when the app has the minimum credentials needed to fetch + run.
    /// `langfuseHost` is always set (defaulted), so we don't gate on it.
    var isConfigured: Bool {
        !langfusePublicKey.isEmpty && !langfuseSecretKey.isEmpty && !openrouterApiKey.isEmpty
    }

    func save() {
        SecretsStore.write("LANGFUSE_PUBLIC_KEY", value: langfusePublicKey)
        SecretsStore.write("LANGFUSE_SECRET_KEY", value: langfuseSecretKey)
        SecretsStore.write("LANGFUSE_HOST", value: langfuseHost)
        SecretsStore.write("OPENROUTER_API_KEY", value: openrouterApiKey)
    }

    /// Build a Langfuse client from the current credentials.
    /// Caller is responsible for not invoking this when `isConfigured` is false.
    func makeLangfuseClient() -> LangfuseClient {
        LangfuseClient(
            publicKey: langfusePublicKey,
            secretKey: langfuseSecretKey,
            host: langfuseHost
        )
    }
}
