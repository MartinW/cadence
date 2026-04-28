import Foundation

/// Mirror of the @promptflow/core types — just enough to deserialise Langfuse
/// responses for read-only consumption. We don't author prompts from the
/// mobile app, so write-side types live in the web/CLI codepaths only.

struct PromptMeta: Decodable, Identifiable, Hashable {
    let name: String
    let versions: [Int]
    let labels: [String]
    let tags: [String]
    let lastUpdatedAt: String

    var id: String { name }

    var latestVersion: Int { versions.max() ?? 0 }
}

/// Chat-message payload returned by Langfuse for chat prompts. The `type`
/// discriminator is dropped on read, so we identify by field shape: a message
/// with `role` is a regular chat message; a placeholder has `name` instead.
struct ChatMessage: Decodable, Hashable {
    let role: String
    let content: String
}

/// `text` prompts have a single string body; `chat` prompts have an array.
enum PromptBody: Hashable {
    case text(String)
    case chat([ChatMessage])

    var variables: [String] {
        switch self {
        case .text(let body):
            return TemplateRenderer.extractVariables(from: body)
        case .chat(let messages):
            var seen = Set<String>()
            var ordered: [String] = []
            for m in messages {
                for v in TemplateRenderer.extractVariables(from: m.content) where !seen.contains(v) {
                    seen.insert(v)
                    ordered.append(v)
                }
            }
            return ordered
        }
    }
}

/// PromptFlow's convention for stashing per-prompt knobs inside Langfuse's
/// freeform `config` field. We read two keys today:
///   - `defaults` — pre-fill values for `{{vars}}` (e.g. `user_context`)
///   - `voice` — preferred OpenAI voice id when this prompt runs in Cadence
///                (e.g. "onyx" for a fitness coach, "shimmer" for meditation)
/// Other config keys (max_tokens, temperature, …) are intentionally ignored
/// on the mobile side.
struct PromptConfig: Decodable {
    let defaults: [String: String]?
    let voice: String?
}

struct Prompt: Decodable, Hashable {
    let name: String
    let version: Int
    let body: PromptBody
    let labels: [String]
    let tags: [String]
    let commitMessage: String?
    let defaults: [String: String]
    let voice: String?

    private enum CodingKeys: String, CodingKey {
        case name, version, type, prompt, labels, tags, commitMessage, config
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(Int.self, forKey: .version)
        self.labels = (try? c.decode([String].self, forKey: .labels)) ?? []
        self.tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        self.commitMessage = try c.decodeIfPresent(String.self, forKey: .commitMessage)

        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self.body = .text(try c.decode(String.self, forKey: .prompt))
        case "chat":
            self.body = .chat(try c.decode([ChatMessage].self, forKey: .prompt))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown prompt type: \(type)"
            )
        }

        // `config` is freeform JSON. Decode our known fields leniently — if it
        // contains an exotic shape (e.g. non-string defaults), fall back to
        // empty rather than failing the whole prompt.
        if let cfg = try? c.decode(PromptConfig.self, forKey: .config) {
            self.defaults = cfg.defaults ?? [:]
            self.voice = cfg.voice
        } else {
            self.defaults = [:]
            self.voice = nil
        }
    }
}
