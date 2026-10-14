import Foundation

/// Errors returned by the gateway API.
struct GatewayError: Error, Decodable, LocalizedError {
    let message: String
    let type: String?
    let param: String?
    let code: String?
    
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
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    /// Makes a JSON request to the gateway.
    func request<T: Decodable>(
        endpoint: EndpointType,
        body: some Encodable,
        as responseType: T.Type
    ) async throws -> T {
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        let url = plan.baseURL.appendingPathComponent(plan.path)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
        if let proxy = plan.proxy {
            request.setValue(proxy.absoluteString, forHTTPHeaderField: "X-Proxy-URL")
        }
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw errorResponse.error
            }
            throw GatewayClientError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Makes a multipart form request (for image edits, audio transcriptions).
    func uploadMultipart<T: Decodable>(
        endpoint: EndpointType,
        parts: [MultipartPart],
        as responseType: T.Type
    ) async throws -> T {
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        let url = plan.baseURL.appendingPathComponent(plan.path)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
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
        
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: responseData) {
                throw errorResponse.error
            }
            throw GatewayClientError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: responseData)
    }
    
    /// Downloads binary data (for TTS audio, video content).
    func downloadBinary(endpoint: EndpointType, body: some Encodable) async throws -> Data {
        let plan = try GatewayConfigurationStore.shared.plan(for: endpoint)
        let url = plan.baseURL.appendingPathComponent(plan.path)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(plan.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = plan.timeout
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw errorResponse.error
            }
            throw GatewayClientError.httpError(httpResponse.statusCode)
        }
        
        return data
    }
    
    /// Tests connectivity to a channel by making a simple request.
    func testConnection(channel: ProviderChannel, apiKey: String) async throws -> Bool {
        let url = channel.baseURL.appendingPathComponent("/v1/models")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200...299).contains(httpResponse.statusCode)
    }
}

/// A part of a multipart form request.
struct MultipartPart {
    let name: String
    let content: Content
    
    enum Content {
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

enum GatewayClientError: Error, LocalizedError {
    case noChannelAvailable
    case missingAPIKey(String)
    case invalidResponse
    case httpError(Int)
    
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
        }
    }
}
