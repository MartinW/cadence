import SwiftUI

@main
struct CadenceApp: App {
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
        }
    }
}

/// Top-level routing — push the user into Settings until creds are filled in,
/// otherwise show the prompt list. Keeping it dumb keeps onboarding obvious.
struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            if settings.isConfigured {
                PromptListView()
            } else {
                SettingsView(isFirstRun: true)
            }
        }
    }
}
