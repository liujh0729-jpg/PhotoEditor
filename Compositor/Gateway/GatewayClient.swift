import Foundation

/// Errors returned by the gateway API.
struct GatewayError: Error, Decodable, LocalizedError {
    let message: String
    let type: String?
    let param: String?
    /// Gateways return the code as either a string ("invalid_request_error") or a number (429), so it's kept
    /// lenient; a strict `String?` would fail to decode the whole error body and hide the real message.
    let code: AnyCodable?
    
    var errorDescription: String? {
        message
    }
}

/// Wrapper for OpenAI-style error responses.
private struct ErrorResponse: Decodable {
    let error: GatewayError
}

/// Async HTTP client for the gateway, using URLSession. The whole module defaults to main-actor isolation,
/// and every request suspends on URLSession rather than blocking, so this stays on the main actor too.
final class GatewayClient {
    static let shared = GatewayClient()
    
    private let session: URLSession
    /// Sessions built for channels that name a proxy, keyed by proxy URL, so we don't spin one up per request.
    private var proxySessions: [String: URLSession] = [:]
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    /// Joins a channel's base URL and an endpoint path without doubling the `/v1` prefix when the base already
    /// carries it (e.g. `https://api.x/v1` + `/v1/chat/completions`).
    private func makeURL(base: URL, path: String) -> URL {
        var path = path
        if base.path.hasSuffix("/v1"), path.hasPrefix("/v1") {
            path.removeFirst(3)
        }
        return base.appendingPathComponent(path)
    }
    
    /// The session to run a request on: the shared one, or a proxy-configured one when the channel names a proxy.
    private func session(for plan: GatewayRequestPlan) -> URLSession {
        Self.configuredSession(base: session, proxy: plan.proxy, timeout: plan.timeout, cache: &proxySessions)
    }
    
    /// Raises a gateway error for a non-2xx response, decoding the OpenAI-style error body when it's there.
    private static func validate(_ response: URLResponse, _ data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw errorResponse.error
            }
            throw GatewayClientError.httpError(httpResponse.statusCode)
        }
    }
    
    /// Privacy Mode keeps the Mac silent: checked before a byte of a request is built, so nothing is sent
    /// while it's on — no pixels, no prompts, no audio.
    private static func guardPrivacy() throws {
        if GatewayConfigurationStore.shared.privacyMode {
            throw GatewayClientError.privacyMode
        }
    }
    
    /// Builds (and caches) a session that routes through `proxy`, falling back to the shared session when none is set.
    private static func configuredSession(base: URLSession, proxy: URL?, timeout: TimeInterval,
                                          cache: inout [String: URLSession]) -> URLSession {
        guard let proxy, let host = proxy.host else { return base }
        let key = proxy.absoluteString
        if let cached = cache[key] { return cached }
        let scheme = proxy.scheme?.lowercased() ?? "http"
        let port = proxy.port ?? (scheme == "socks" || scheme == "socks5" ? 1080 : 8080)
        var dictionary: [String: Any]
        switch scheme {
        case "socks", "socks5":
            dictionary = ["SOCKSEnable": true, "SOCKSHost": host, "SOCKSPort": port]
        case "https":
            dictionary = ["HTTPSEnable": true, "HTTPSProxy": host, "HTTPSPort": port]
        default:
            dictionary = ["HTTPEnable": true, "HTTPProxy": host, "HTTPPort": port]
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = 300
        config.connectionProxyDictionary = dictionary
        let built = URLSession(configuration: config)
        cache[key] = built
        return built
    }
    
    /// Makes a JSON request to the gateway.
    func request<T: Decodable>(
        endpoint: EndpointType,
        body: some Encodable,
        as responseType: T.Type
    ) async throws -> T {
        try Self.guardPrivacy()
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        
        var request = URLRequest(url: makeURL(base: plan.baseURL, path: plan.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session(for: plan).data(for: request)
        try Self.validate(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Fetches a resource by path with the endpoint's channel credentials (used to poll async task status),
    /// so the response's status code is checked rather than silently decoded.
    func get<T: Decodable>(
        endpoint: EndpointType,
        path: String,
        as responseType: T.Type
    ) async throws -> T {
        try Self.guardPrivacy()
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        
        var request = URLRequest(url: makeURL(base: plan.baseURL, path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
        let (data, response) = try await session(for: plan).data(for: request)
        try Self.validate(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Makes a multipart form request (for image edits, audio transcriptions).
    func uploadMultipart<T: Decodable>(
        endpoint: EndpointType,
        parts: [MultipartPart],
        as responseType: T.Type
    ) async throws -> T {
        try Self.guardPrivacy()
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: makeURL(base: plan.baseURL, path: plan.path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
        // Concatenating multi-megabyte PNG payloads is real work; do it on the global executor so the
        // editor doesn't stall while an edit's request body comes together.
        request.httpBody = await Task.detached(priority: .userInitiated) {
            Self.buildMultipartBody(parts: parts, boundary: boundary)
        }.value
        
        let (responseData, response) = try await session(for: plan).data(for: request)
        try Self.validate(response, responseData)
        return try JSONDecoder().decode(T.self, from: responseData)
    }
    
    /// Downloads binary data (for TTS audio, video content).
    func downloadBinary(endpoint: EndpointType, body: some Encodable) async throws -> Data {
        try Self.guardPrivacy()
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        
        var request = URLRequest(url: makeURL(base: plan.baseURL, path: plan.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session(for: plan).data(for: request)
        try Self.validate(response, data)
        return data
    }
    
    /// Builds the raw multipart/form-data body. `nonisolated` so it can run on the global executor for
    /// large payloads without the MainActor serialization stall that an inline `Data.append` loop would hit.
    nonisolated static func buildMultipartBody(parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            switch part.content {
            case .text(let value):
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            case .data(let data, let filename, let mimeType):
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
    
    /// Fetches a raw GET payload using a specific channel and API key, honoring the channel's proxy and timeout.
    /// Used by catalog discovery, which lives outside the fixed capability slots on `EndpointType`.
    func fetchRaw(channel: ProviderChannel, apiKey: String, path: String) async throws -> Data {
        try Self.guardPrivacy()
        var request = URLRequest(url: makeURL(base: channel.baseURL, path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = channel.timeout
        let (data, response) = try await Self.configuredSession(base: session, proxy: channel.proxy, timeout: channel.timeout, cache: &proxySessions).data(for: request)
        try Self.validate(response, data)
        return data
    }
    
    /// Tests connectivity to a channel by making a simple request.
    func testConnection(channel: ProviderChannel, apiKey: String) async throws -> Bool {
        var request = URLRequest(url: makeURL(base: channel.baseURL, path: "/v1/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        var cache: [String: URLSession] = [:]
        let urlSession = Self.configuredSession(base: session, proxy: channel.proxy, timeout: 10, cache: &cache)
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200...299).contains(httpResponse.statusCode)
    }
}

/// A part of a multipart form request. Sendable so the body builder can run off the main actor.
struct MultipartPart: Sendable {
    let name: String
    let content: Content
    
    enum Content: Sendable {
        case text(String)
        case data(Data, filename: String, mimeType: String)
    }
    
    static func text(_ name: String, _ value: String) -> MultipartPart {
        MultipartPart(name: name, content: .text(value))
    }
    
    static func data(_ name: String, _ data: Data, filename: String, mimeType: String) -> MultipartPart {
        MultipartPart(name: name, content: .data(data, filename: filename, mimeType: mimeType))
    }
}

/// Client-side failures raised before a request goes out. `Equatable` so tests can pin down which refusal fired.
enum GatewayClientError: Error, LocalizedError, Equatable {
    case noChannelAvailable
    case missingAPIKey(String)
    case invalidResponse
    case httpError(Int)
    case privacyMode
    
    var errorDescription: String? {
        switch self {
        case .noChannelAvailable:
            return "No enabled channel available"
        case .missingAPIKey(let channelName):
            return "Missing API key for \(channelName)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .privacyMode:
            return "Privacy Mode is on, so nothing is sent to the gateway. Turn it off in Settings › General."
        }
    }
}
