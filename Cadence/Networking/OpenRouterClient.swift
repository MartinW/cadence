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
            audio: nil,
            stream: false,
            user: nil,
            session_id: nil,
            trace: nil
        )
        let response = try await sendChat(body: body)
        guard let text = response.choices.first?.message.content else {
            throw OpenRouterError.malformedResponse("missing message.content")
        }
        return text
    }

    // MARK: - Voice prompt run (single-step text + audio)

    /// Run a voice prompt as a single audio-completion call.
    ///
    /// Why single-step instead of "Claude reasons → audio model reads"?
    /// OpenRouter only exposes `/chat/completions`, not OpenAI's dedicated
    /// `/audio/speech` endpoint, and chat models don't have a verbatim-read
    /// mode — they always generate a fresh response. So a two-step flow
    /// produces audio that diverges from the displayed transcript.
    ///
    /// We send the prompt's messages straight to the audio model. It
    /// produces matching transcript + audio bytes in one streamed response,
    /// which we accumulate together so the UI can show exactly what was
    /// spoken.
    ///
    /// Streaming audio only supports `pcm16` — the bytes we get back are
    /// raw 24kHz mono signed-16-bit PCM, which we wrap in a WAV header so
    /// AVAudioPlayer can play them directly.
    ///
    /// Observability fields (`sessionId`, `userId`, `traceName`) are forwarded
    /// to Langfuse via OpenRouter's Broadcast feature.
    func runVoicePrompt(
        model: String,
        messages: [ChatMessageInput],
        voice: String = "alloy",
        sessionId: String,
        userId: String,
        traceName: String
    ) async throws -> VoiceRunResult {
        let body = ChatRequest(
            model: model,
            messages: messages,
            modalities: ["text", "audio"],
            audio: AudioConfig(voice: voice, format: "pcm16"),
            stream: true,
            user: userId,
            session_id: sessionId,
            trace: TraceMetadata(trace_name: traceName, app: "cadence")
        )

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://github.com/MartinW/cadence", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Cadence", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.malformedResponse("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody.append(line)
                errorBody.append("\n")
                if errorBody.count > 2000 { break }
            }
            throw OpenRouterError.upstream(status: http.statusCode, body: errorBody)
        }

        var audioData = Data()
        var transcript = ""
        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let chunkData = payload.data(using: .utf8) else { continue }
            guard let chunk = try? decoder.decode(StreamChunk.self, from: chunkData) else {
                continue
            }
            if let delta = chunk.choices.first?.delta?.audio {
                if let audioBase64 = delta.data,
                   !audioBase64.isEmpty,
                   let decoded = Data(base64Encoded: audioBase64) {
                    audioData.append(decoded)
                }
                if let chunkTranscript = delta.transcript, !chunkTranscript.isEmpty {
                    transcript.append(chunkTranscript)
                }
            }
        }

        if audioData.isEmpty {
            throw OpenRouterError.malformedResponse("audio stream produced no data")
        }
        // OpenAI/OpenRouter return mono 24kHz signed-16-bit-LE PCM. AVAudioPlayer
        // can't play raw PCM directly — wrap it in a WAV header so it sees a
        // self-describing audio file.
        let wav = WAVPacker.wrap(pcmData: audioData, sampleRate: 24_000, channels: 1)
        return VoiceRunResult(transcript: transcript, audioWAV: wav)
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

// MARK: - Public results

/// Combined transcript + audio bytes from a voice run. They come from the
/// same streamed response, so the transcript matches the audio by construction.
struct VoiceRunResult: Sendable {
    let transcript: String
    let audioWAV: Data
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
    var stream: Bool? = nil
    let user: String?
    let session_id: String?
    let trace: TraceMetadata?
}

struct TraceMetadata: Encodable, Sendable {
    let trace_name: String
    let app: String
}

/// SSE chunk for streaming audio responses.
///
/// Each `data:` line in the stream decodes to one of these. We only care
/// about the audio bytes; transcript chunks come through too but we already
/// have the verbatim text from the Claude step.
struct StreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            struct AudioDelta: Decodable, Sendable {
                let data: String?
                let transcript: String?
            }
            let audio: AudioDelta?
        }
        let delta: Delta?
    }
    let choices: [Choice]
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
