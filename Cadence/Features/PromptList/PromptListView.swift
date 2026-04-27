import SwiftUI

@MainActor
@Observable
final class PromptListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([PromptMeta])
        case failed(String)
    }

    var state: LoadState = .idle

    /// Fetch all prompts and filter to the `voice:*` namespace. Cadence
    /// deliberately doesn't surface non-voice prompts so authors can keep one
    /// Langfuse project and let the consumer-app filter by tag namespace.
    func load(client: LangfuseClient) async {
        state = .loading
        do {
            let all = try await client.listPrompts(limit: 100)
            let voice = all.filter { $0.tags.anyIn(namespace: .voice) }
            state = .loaded(voice.sorted { $0.name < $1.name })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct PromptListView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = PromptListViewModel()
    @State private var showSettings = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorState(message: message) {
                    Task { await reload() }
                }
            case .loaded(let prompts) where prompts.isEmpty:
                ContentUnavailableView(
                    "No voice prompts",
                    systemImage: "waveform.slash",
                    description: Text("Tag a prompt with `voice` (or `voice:*`) in PromptFlow to see it here.")
                )
            case .loaded(let prompts):
                List(prompts) { meta in
                    NavigationLink(value: meta) {
                        PromptRow(meta: meta)
                    }
                }
                .refreshable { await reload() }
            }
        }
        .navigationTitle("Cadence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .navigationDestination(for: PromptMeta.self) { meta in
            PromptRunPlaceholderView(meta: meta)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showSettings = false }
                        }
                    }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        guard settings.isConfigured else { return }
        await viewModel.load(client: settings.makeLangfuseClient())
    }
}

private struct PromptRow: View {
    let meta: PromptMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meta.name)
                .font(.headline)
                .monospaced()
            HStack(spacing: 8) {
                Text("v\(meta.latestVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let voiceTags = meta.tags.filter(namespace: .voice)
                if !voiceTags.isEmpty {
                    Text(voiceTags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Placeholder for the run flow. Wired in the next iteration alongside the
/// OpenRouter client + audio playback.
struct PromptRunPlaceholderView: View {
    let meta: PromptMeta

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(meta.name)
                .font(.title2.weight(.semibold))
                .monospaced()
            Text("Run flow ships in the next iteration.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
}
