import SwiftUI

@main
struct CadenceApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if AppConfig.shared.isConfigured {
                    CoachListView()
                } else {
                    MissingConfigView()
                }
            }
        }
    }
}

/// Surfaced when `Cadence-Secrets.xcconfig` wasn't filled in at build time.
/// This is a developer-facing message — there's no end-user UI for fixing
/// it because credentials are build-time-only by design.
private struct MissingConfigView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Build-time config missing")
                .font(.headline)
            Text("Fill in `Cadence-Secrets.xcconfig` with real keys and rebuild.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
