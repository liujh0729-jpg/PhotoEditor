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
        /// What a million prompt tokens costs, on the chat-shaped slots.
        var promptPerMillion: Double? = nil
        /// What one picture costs, per resolution tier, on the image-shaped slots.
        var imagePricing: ImagePricing? = nil
        /// What one picture costs, keyed by resolution label, when the catalog spells it out that way.
        var byResolution: [String: Double]? = nil
        /// The gateway's coin rate: a price times this reads in the credits the gateway bills.
        var awcoinRate: Double? = nil

        struct ImagePricing: Codable {
            var tiers: [Tier]? = nil

            struct Tier: Codable {
                var resolution: String? = nil
                var price: Double? = nil
            }
        }
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
        // Privacy Mode: the catalog lives on the gateway too, so nothing is fetched and the cached list stays shown.
        if GatewayConfigurationStore.shared.privacyMode { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let store = GatewayConfigurationStore.shared
        guard let channel = store.configuration.activeChannel else {
            throw CatalogError.noChannel
        }
        
        guard let apiKey = try KeychainStore.shared.retrieve(for: channel.id) else {
            throw CatalogError.missingAPIKey
        }
        
        // Try /v1/new-api/catalog first (an AIPDD extension); fall back to OpenAI-style /v1/models on any
        // failure (missing endpoint, non-2xx, undecodable body). GatewayClient's fetchRaw checks the status
        // code and honors the channel's proxy, so a 4xx never masquerades as a valid catalog.
        do {
            let data = try await GatewayClient.shared.fetchRaw(
                channel: channel, apiKey: apiKey, path: "/v1/new-api/catalog"
            )
            let catalogResponse = try JSONDecoder().decode(CatalogResponse.self, from: data)
            
            capabilities = catalogResponse.capabilities
            models = catalogResponse.models
            lastSynced = Date()
            
            saveCache(baseURL: channel.baseURL.absoluteString, data: data)
        } catch {
            try await syncFallback(channel: channel, apiKey: apiKey)
        }
    }
    
    /// Fallback sync using /v1/models endpoint.
    private func syncFallback(channel: ProviderChannel, apiKey: String) async throws {
        let data = try await GatewayClient.shared.fetchRaw(
            channel: channel, apiKey: apiKey, path: "/v1/models"
        )
        
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
    
    /// What one request against a slot costs as the catalog spells it out, in the words the AI sheets show
    /// before submitting. A catalog that says nothing — or isn't there at all — reads "Cost unknown".
    func estimate(for endpointType: EndpointType, prompt: String? = nil) -> String {
        let pricing = capabilities(for: endpointType).first?.pricing
        if let credits = CostEstimate.credits(for: pricing, prompt: prompt) {
            return String(format: NSLocalizedString("≈ %@ credits", comment: ""),
                          credits == 0 ? "0" : String(format: "%.3g", credits))
        }
        return NSLocalizedString("Cost unknown", comment: "")
    }
    
    /// Saves the catalog to cache.
    private func saveCache(baseURL: String, data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
    }
    
    /// Loads the catalog from cache, but only if it was saved for the currently-active channel — a catalog
    /// cached under one gateway would otherwise silently shape model choices for another.
    private func loadCache() {
        let currentBase = GatewayConfigurationStore.shared.configuration.activeChannel?.baseURL.absoluteString
        guard let cachedBase = UserDefaults.standard.string(forKey: baseURLKey),
              cachedBase == currentBase,
              let data = UserDefaults.standard.data(forKey: cacheKey),
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
