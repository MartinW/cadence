import Foundation

/// Read-only Langfuse client.
///
/// Cadence only ever pulls prompts — authoring lives in PromptFlow Web. We
/// hit the public REST API directly with HTTP Basic auth (public:secret) so
/// there's no SDK dependency to manage on iOS.
actor LangfuseClient {
    private let publicKey: String
    private let secretKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    init(publicKey: String, secretKey: String, host: String) {
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.baseURL = URL(string: host) ?? URL(string: "https://cloud.langfuse.com")!
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }

    /// List prompt metadata. Pass `tag` to narrow at the server, or filter
    /// in-process for AND-of-tags semantics.
    func listPrompts(tag: String? = nil, limit: Int = 100) async throws -> [PromptMeta] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/public/v2/prompts"),
            resolvingAgainstBaseURL: true
        )!
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let tag {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        components.queryItems = query

        let request = makeRequest(url: components.url!)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, body: data)
        let envelope = try JSONDecoder().decode(PromptListResponse.self, from: data)
        return envelope.data
    }

    /// Get a specific prompt. With no version/label, defaults to the auto-applied
    /// "latest" label so draft-only prompts still resolve (matching @promptflow/core).
    func getPrompt(name: String, version: Int? = nil, label: String? = nil) async throws -> Prompt {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/public/v2/prompts/\(encoded)"),
            resolvingAgainstBaseURL: true
        )!
        var query: [URLQueryItem] = []
        if let version {
            query.append(URLQueryItem(name: "version", value: String(version)))
        } else if let label {
            query.append(URLQueryItem(name: "label", value: label))
        } else {
            query.append(URLQueryItem(name: "label", value: "latest"))
        }
        components.queryItems = query

        let request = makeRequest(url: components.url!)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, body: data)
        return try JSONDecoder().decode(Prompt.self, from: data)
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let credential = "\(publicKey):\(secretKey)"
        let token = Data(credential.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Map non-2xx responses into typed errors before they bubble to the UI.
    private func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw LangfuseError.unauthorised
        case 404:
            throw LangfuseError.notFound
        case 429:
            throw LangfuseError.rateLimited
        default:
            let message = String(data: body, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LangfuseError.upstream(status: http.statusCode, body: message)
        }
    }
}

enum LangfuseError: LocalizedError {
    case unauthorised
    case notFound
    case rateLimited
    case upstream(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .unauthorised:
            return "Langfuse rejected the credentials. Check your public + secret keys in Settings."
        case .notFound:
            return "Prompt not found."
        case .rateLimited:
            return "Langfuse rate limit hit — retry shortly."
        case .upstream(let status, let body):
            return "Langfuse error \(status): \(body)"
        }
    }
}

private struct PromptListResponse: Decodable {
    let data: [PromptMeta]
}
