import Foundation

/// OpenRouter is Cadence's single LLM gateway — same key handles both the
/// Claude reasoning step and the audio-out step.
///
/// Two-step pipeline:
///   1. `generateText(...)` — send the rendered prompt to a Claude model, get
///      back text. This is the "thinking" step.
///   2. `synthesizeAudio(...)` — send the resulting text to an audio-output
///      model (e.g. openai/gpt-4o-audio-preview), get back base64-encoded
///      audio bytes that AVAudioPlayer can play directly.
///
/// Keeping the two calls explicit (rather than asking one omni model to do
/// both) preserves Claude as the reasoning brain — which is what the user
/// has authored their prompts for.
actor OpenRouterClient {
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Text generation (Claude)

    func generateText(
        model: String,
        messages: [ChatMessageInput]
    ) async throws -> String {
        let body = ChatRequest(
            model: model,
            messages: messages,
            modalities: nil,
            audio: nil
        )
        let response = try await sendChat(body: body)
        guard let text = response.choices.first?.message.content else {
            throw OpenRouterError.malformedResponse("missing message.content")
        }
        return text
    }

    // MARK: - Audio synthesis

    /// Render `text` as audio.
    ///
    /// The trick to using a reasoning model as a text-to-speech engine is
    /// telling it to read verbatim — without that instruction it will try to
    /// "respond" rather than narrate. The system message below is short on
    /// purpose; longer instructions tend to bleed into the spoken output.
    func synthesizeAudio(
        model: String,
        text: String,
        voice: String = "alloy",
        format: String = "wav"
    ) async throws -> Data {
        let messages = [
            ChatMessageInput(
                role: "system",
                content: "You are a text-to-speech engine. Read the user's message aloud verbatim, with natural pacing. Do not add commentary, do not paraphrase."
            ),
            ChatMessageInput(role: "user", content: text),
        ]
        let body = ChatRequest(
            model: model,
            messages: messages,
            modalities: ["text", "audio"],
            audio: AudioConfig(voice: voice, format: format)
        )
        let response = try await sendChat(body: body)
        guard let audio = response.choices.first?.message.audio else {
            throw OpenRouterError.malformedResponse("missing message.audio")
        }
        guard let data = Data(base64Encoded: audio.data) else {
            throw OpenRouterError.malformedResponse("invalid base64 in audio.data")
        }
        return data
    }

    // MARK: - Internal HTTP

    private func sendChat(body: ChatRequest) async throws -> ChatResponse {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/MartinW/cadence", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Cadence", forHTTPHeaderField: "X-Title")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.malformedResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "(no body)"
            throw OpenRouterError.upstream(status: http.statusCode, body: snippet)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }
}

// MARK: - Wire types

struct ChatMessageInput: Encodable, Sendable {
    let role: String
    let content: String
}

struct AudioConfig: Encodable, Sendable {
    let voice: String
    let format: String
}

struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessageInput]
    let modalities: [String]?
    let audio: AudioConfig?
}

struct ChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let content: String?
            let audio: AudioPayload?

            struct AudioPayload: Decodable, Sendable {
                let data: String
                let transcript: String?
            }
        }
        let message: Message
    }
    let choices: [Choice]
}

enum OpenRouterError: LocalizedError {
    case malformedResponse(String)
    case upstream(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail):
            return "OpenRouter returned a malformed response: \(detail)"
        case .upstream(let status, let body):
            // Truncate so a giant error body doesn't blow up a SwiftUI alert.
            let trimmed = body.prefix(300)
            return "OpenRouter \(status) — \(trimmed)"
        }
    }
}
