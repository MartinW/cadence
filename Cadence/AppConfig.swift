import Foundation

/// Build-time configuration, populated from `Cadence-Secrets.xcconfig`
/// (gitignored) → Info.plist substitutions → `Bundle.main`.
///
/// There is no in-app onboarding for credentials; this is a personal-use /
/// TestFlight app where keys are baked into the build. The xcconfig file
/// stays out of source control, so secrets never land on GitHub.
///
/// `AppConfig.shared` is a process-wide singleton that reads once at startup
/// and caches; mutations require a rebuild.
struct AppConfig {
    let langfusePublicKey: String
    let langfuseSecretKey: String
    let langfuseHost: String
    let openrouterApiKey: String

    /// True when every required key resolved to a non-empty, non-placeholder
    /// value. If false, the build was made without filling in
    /// Cadence-Secrets.xcconfig and the prompt list will surface a clear
    /// "missing config" error rather than failing silently with auth errors.
    var isConfigured: Bool {
        ![
            langfusePublicKey,
            langfuseSecretKey,
            openrouterApiKey,
        ].contains(where: { $0.isEmpty || $0.contains("...") })
    }

    static let shared: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppConfig(
            langfusePublicKey: read(info, "CadenceLangfusePublicKey"),
            langfuseSecretKey: read(info, "CadenceLangfuseSecretKey"),
            langfuseHost: {
                let raw = read(info, "CadenceLangfuseHost")
                return raw.isEmpty ? "https://cloud.langfuse.com" : raw
            }(),
            openrouterApiKey: read(info, "CadenceOpenRouterApiKey")
        )
    }()

    /// Stable per-install identifier sent to Langfuse as `user`. Generated on
    /// first launch and persisted in UserDefaults — placeholder until Cadence
    /// grows a real account concept, at which point swap this for the real
    /// user ID at the call site.
    static let userId: String = {
        let key = "CadenceUserId"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }()

    private static func read(_ info: [String: Any], _ key: String) -> String {
        (info[key] as? String) ?? ""
    }
}
