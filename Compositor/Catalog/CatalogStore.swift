import Foundation
import Combine

/// Represents a capability from the gateway catalog.
struct CatalogCapability: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let description: String
    let adapterCode: String
    let endpointType: String
    let taskKind: String
    let inputModalities: [String]
    let outputModalities: [String]
    let available: Bool?
    let execution: Execution
    let pricing: Pricing
    
    struct Execution: Codable {
        let protocolName: String
        let path: String

        private enum CodingKeys: String, CodingKey {
            case protocolName = "protocol"
            case path
        }
    }
    
    struct Pricing: Codable {
        let pricingModel: String
        let currency: String
        let enabled: Bool
        var free: Bool? = nil
    }
}

/// Represents a model from the gateway catalog.
struct CatalogModel: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let inputModalities: [String]
    let outputModalities: [String]
    let available: Bool
    let execution: CatalogCapability.Execution
    let pricing: CatalogCapability.Pricing
}

/// The complete catalog response.
struct CatalogResponse: Codable {
    let schemaVersion: Int
    let revision: String
    let generatedAt: String
    let capabilities: [CatalogCapability]
    let models: [CatalogModel]
}

/// Manages the capability catalog from the gateway.
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()
    
    @Published private(set) var capabilities: [CatalogCapability] = []
    @Published private(set) var models: [CatalogModel] = []
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isSyncing: Bool = false
    
    private let cacheKey = "gateway.catalog.cache"
    private let baseURLKey = "gateway.catalog.baseURL"
    
    private init() {
        loadCache()
    }
    
    /// Syncs the catalog from the gateway.
    func sync() async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        let store = GatewayConfigurationStore.shared
        guard let channel = store.configuration.activeChannel else {
            throw CatalogError.noChannel
        }
        
        guard let apiKey = try KeychainStore.shared.retrieve(for: channel.id) else {
            throw CatalogError.missingAPIKey
        }
        
        // Try to fetch from /v1/new-api/catalog first
        let catalogURL = channel.baseURL.appendingPathComponent("/v1/new-api/catalog")
        
        var request = URLRequest(url: catalogURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // Fallback to /v1/models
                try await syncFallback(channel: channel, apiKey: apiKey)
                return
            }
            
            let catalogResponse = try JSONDecoder().decode(CatalogResponse.self, from: data)
            
            capabilities = catalogResponse.capabilities
            models = catalogResponse.models
            lastSynced = Date()
            
            // Cache the response
            saveCache(baseURL: channel.baseURL.absoluteString, data: data)
        } catch {
            // Fallback to /v1/models
            try await syncFallback(channel: channel, apiKey: apiKey)
        }
    }
    
    /// Fallback sync using /v1/models endpoint.
    private func syncFallback(channel: ProviderChannel, apiKey: String) async throws {
        let modelsURL = channel.baseURL.appendingPathComponent("/v1/models")
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct ModelsResponse: Codable {
            let data: [ModelInfo]
            
            struct ModelInfo: Codable {
                let id: String
            }
        }
        
        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        
        // Convert to CatalogModel
        models = modelsResponse.data.map { info in
            CatalogModel(
                id: info.id,
                name: info.id,
                description: "",
                inputModalities: [],
                outputModalities: [],
                available: true,
                execution: .init(protocolName: "openai", path: "/v1/chat/completions"),
                pricing: .init(pricingModel: "unknown", currency: "USD", enabled: false)
            )
        }
        
        capabilities = []
        lastSynced = Date()
    }
    
    /// Returns models available for a specific endpoint type.
    func models(for endpointType: EndpointType) -> [CatalogModel] {
        models.filter { model in
            // Simple heuristic: check if the model's execution path matches
            model.execution.path.contains(endpointType.defaultPath) ||
            model.outputModalities.contains(where: { $0.contains(endpointType.rawValue) })
        }
    }
    
    /// Returns capabilities for a specific endpoint type.
    func capabilities(for endpointType: EndpointType) -> [CatalogCapability] {
        capabilities.filter { $0.endpointType == endpointType.rawValue }
    }
    
    /// Saves the catalog to cache.
    private func saveCache(baseURL: String, data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
    }
    
    /// Loads the catalog from cache.
    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let response = try? JSONDecoder().decode(CatalogResponse.self, from: data) else {
            return
        }
        
        capabilities = response.capabilities
        models = response.models
    }
}

enum CatalogError: Error, LocalizedError {
    case noChannel
    case missingAPIKey
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .noChannel:
            return "No active channel"
        case .missingAPIKey:
            return "Missing API key"
        case .syncFailed:
            return "Catalog sync failed"
        }
    }
}
