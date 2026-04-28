import SwiftUI

@MainActor
@Observable
final class CoachDetailViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded([PromptMeta])
        case failed(String)
    }

    var state: LoadState = .idle

    /// Pull all prompts and filter to the ones tagged for this coach. We
    /// filter client-side rather than passing the tag through Langfuse's
    /// `?tag=` query because that filter only matches a single tag at a
    /// time and we want AND semantics with `voice` if we ever add it.
    func load(client: LangfuseClient, coachTag: String) async {
        state = .loading
        do {
            let all = try await client.listPrompts(limit: 100)
            let filtered = all
                .filter { $0.tags.contains(coachTag) }
                .sorted { $0.name < $1.name }
            state = .loaded(filtered)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct CoachDetailView: View {
    let coach: Coach

    @State private var viewModel = CoachDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                bio
                Divider()
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle(coach.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PromptMeta.self) { meta in
            PromptRunView(meta: meta)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .background(Color(.systemGroupedBackground))
    }

    private var bio: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(coach.accentColor.opacity(0.15))
                Image(systemName: coach.systemImage)
                    .font(.title)
                    .foregroundStyle(coach.accentColor)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(coach.role)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(coach.accentColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(coach.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading prompts…")
                .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            ErrorState(message: message) {
                Task { await reload() }
            }
        case .loaded(let prompts) where prompts.isEmpty:
            ContentUnavailableView(
                "No prompts yet",
                systemImage: "waveform.slash",
                description: Text("Tag a prompt with `\(coach.tag)` in PromptFlow to see it here.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        case .loaded(let prompts):
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(prompts) { meta in
                    NavigationLink(value: meta) {
                        PromptRow(meta: meta, accent: coach.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func reload() async {
        guard AppConfig.shared.isConfigured else { return }
        let config = AppConfig.shared
        let client = LangfuseClient(
            publicKey: config.langfusePublicKey,
            secretKey: config.langfuseSecretKey,
            host: config.langfuseHost
        )
        await viewModel.load(client: client, coachTag: coach.tag)
    }
}

private struct PromptRow: View {
    let meta: PromptMeta
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.body.weight(.medium))
                Text("v\(meta.latestVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Strip the `voice:<coach>:` prefix (when present) so the UI shows just
    /// the scenario name. Falls back to the full prompt name otherwise.
    private var displayTitle: String {
        let parts = meta.name.split(separator: ":")
        if parts.count >= 3 {
            return parts.dropFirst(2).joined(separator: ":").replacingOccurrences(of: "-", with: " ").capitalized
        }
        return meta.name
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Couldn't load prompts")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
