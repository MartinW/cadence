import SwiftUI

/// Models for the run flow.
///
/// Locked decisions (per the architecture plan):
/// - Reasoning model: `anthropic/claude-haiku-4.5` — fastest Claude, lowest
///   latency-to-first-word for voice. Fixed in code, not user-configurable.
/// - Audio model: `openai/gpt-4o-audio-preview` via OpenRouter — accepts text
///   and produces audio bytes in a single call.
private enum RunConfig {
    static let reasoningModel = "anthropic/claude-haiku-4.5"
    static let audioModel = "openai/gpt-4o-audio-preview"
    static let voice = "alloy"
}

@MainActor
@Observable
final class PromptRunViewModel {
    enum Stage: Equatable {
        case loadingPrompt
        case ready
        case thinking
        case speaking
        case played
        case failed(String)
    }

    var stage: Stage = .loadingPrompt
    var variableValues: [String: String] = [:]
    var transcript: String = ""
    private(set) var prompt: Prompt?
    private(set) var audioBytes: Data?

    let promptName: String

    init(promptName: String) {
        self.promptName = promptName
    }

    /// Initial fetch — pulls the prompt and seeds the variable form with
    /// `config.defaults` (e.g. PromptFlow's `user_context` convention).
    func loadPrompt(client: LangfuseClient) async {
        do {
            let p = try await client.getPrompt(name: promptName)
            self.prompt = p
            // Pre-fill from config.defaults; missing variables default to empty.
            var values: [String: String] = [:]
            for v in p.body.variables {
                values[v] = p.defaults[v] ?? ""
            }
            self.variableValues = values
            self.stage = .ready
        } catch {
            self.stage = .failed(error.localizedDescription)
        }
    }

    /// Two-step run: Claude → text, then audio model → bytes, then play.
    /// Stage transitions drive the UI so the user can see progress.
    func run(openRouter: OpenRouterClient, audioPlayer: AudioPlayer) async {
        guard let prompt else { return }
        stage = .thinking
        transcript = ""

        let messages = renderToChatMessages(prompt: prompt, variables: variableValues)

        do {
            let text = try await openRouter.generateText(
                model: RunConfig.reasoningModel,
                messages: messages
            )
            self.transcript = text
            stage = .speaking
            let audio = try await openRouter.synthesizeAudio(
                model: RunConfig.audioModel,
                text: text,
                voice: RunConfig.voice
            )
            self.audioBytes = audio
            try audioPlayer.play(data: audio)
            stage = .played
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Replay the last audio without re-running the LLM. Free, instant.
    func replay(audioPlayer: AudioPlayer) {
        guard let audioBytes else { return }
        do {
            try audioPlayer.play(data: audioBytes)
            stage = .played
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func renderToChatMessages(
        prompt: Prompt,
        variables: [String: String]
    ) -> [ChatMessageInput] {
        switch prompt.body {
        case .text(let body):
            return [
                ChatMessageInput(
                    role: "user",
                    content: TemplateRenderer.render(body, variables: variables)
                ),
            ]
        case .chat(let messages):
            return messages.map {
                ChatMessageInput(
                    role: $0.role,
                    content: TemplateRenderer.render($0.content, variables: variables)
                )
            }
        }
    }
}

struct PromptRunView: View {
    let meta: PromptMeta

    @State private var viewModel: PromptRunViewModel
    @State private var audioPlayer = AudioPlayer()

    init(meta: PromptMeta) {
        self.meta = meta
        _viewModel = State(initialValue: PromptRunViewModel(promptName: meta.name))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let prompt = viewModel.prompt {
                    if !prompt.body.variables.isEmpty {
                        variablesSection
                    }
                    actionSection
                    if !viewModel.transcript.isEmpty {
                        transcriptSection
                    }
                    if case .failed(let message) = viewModel.stage {
                        errorBanner(message)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(meta.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let config = AppConfig.shared
            let client = LangfuseClient(
                publicKey: config.langfusePublicKey,
                secretKey: config.langfuseSecretKey,
                host: config.langfuseHost
            )
            await viewModel.loadPrompt(client: client)
        }
    }

    private var header: some View {
        Group {
            switch viewModel.stage {
            case .loadingPrompt:
                ProgressView()
            case .ready, .played:
                EmptyView()
            case .thinking:
                StageBadge(text: "Thinking…", systemImage: "brain")
            case .speaking:
                StageBadge(text: "Speaking…", systemImage: "waveform")
            case .failed:
                StageBadge(text: "Failed", systemImage: "exclamationmark.triangle", tint: .red)
            }
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(viewModel.prompt?.body.variables ?? [], id: \.self) { name in
                VariableField(
                    name: name,
                    value: Binding(
                        get: { viewModel.variableValues[name] ?? "" },
                        set: { viewModel.variableValues[name] = $0 }
                    )
                )
            }
        }
    }

    private var actionSection: some View {
        HStack {
            Button {
                Task { await runOrReplay() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.stage == .played ? "arrow.clockwise" : "play.fill")
                    Text(buttonLabel)
                        .bold()
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(viewModel.transcript)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Run failed", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var buttonLabel: String {
        switch viewModel.stage {
        case .loadingPrompt: return "Loading…"
        case .ready: return "Speak"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .played: return "Replay"
        case .failed: return "Try again"
        }
    }

    private var isBusy: Bool {
        switch viewModel.stage {
        case .thinking, .speaking, .loadingPrompt:
            return true
        default:
            return false
        }
    }

    private func runOrReplay() async {
        let openRouter = OpenRouterClient(apiKey: AppConfig.shared.openrouterApiKey)
        if viewModel.stage == .played, viewModel.audioBytes != nil {
            viewModel.replay(audioPlayer: audioPlayer)
        } else {
            await viewModel.run(openRouter: openRouter, audioPlayer: audioPlayer)
        }
    }
}

private struct VariableField: View {
    let name: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("{{\(name)}}")
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
            TextField(name, text: $value, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(name == "user_context" ? false : true)
                .textInputAutocapitalization(name == "user_context" ? .sentences : .never)
        }
    }
}

private struct StageBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
    }
}
