import Foundation
import Combine

/// The type of API endpoint a capability slot represents.
enum EndpointType: String, Codable, CaseIterable, Identifiable {
    case chat = "chat"
    case imageGeneration = "image_generation"
    case imageEdits = "image_edits"
    case video = "video"
    case audioSpeech = "audio_speech"
    case embeddings = "embeddings"
    case audioTranscriptions = "audio_transcriptions"
    case systemone = "systemone"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .chat: return "Text Chat"
        case .imageGeneration: return "Image Generation"
        case .imageEdits: return "Image Editing"
        case .video: return "Video Generation"
        case .audioSpeech: return "Text-to-Speech"
        case .embeddings: return "Embeddings"
        case .audioTranscriptions: return "Speech-to-Text"
        case .systemone: return "Decision Model"
        }
    }
    
    var defaultPath: String {
        switch self {
        case .chat: return "/v1/chat/completions"
        case .imageGeneration: return "/v1/images/generations"
        case .imageEdits: return "/v1/images/edits"
        case .video: return "/v1/videos"
        case .audioSpeech: return "/v1/audio/speech"
        case .embeddings: return "/v1/embeddings"
        case .audioTranscriptions: return "/v1/audio/transcriptions"
        case .systemone: return "/v1/systemone"
        }
    }
}

/// A provider channel (e.g., AIPDD, OpenAI, custom gateway).
struct ProviderChannel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    var enabled: Bool
    var priority: Int  // Higher = more preferred
    var weight: Int    // For weighted random selection
    var timeout: TimeInterval
    var proxy: URL?
    var isBuiltIn: Bool  // AIPDD is built-in and can't be deleted
    
    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        enabled: Bool = true,
        priority: Int = 0,
        weight: Int = 10,
        timeout: TimeInterval = 60,
        proxy: URL? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.enabled = enabled
        self.priority = priority
        self.weight = weight
        self.timeout = timeout
        self.proxy = proxy
        self.isBuiltIn = isBuiltIn
    }
}

/// A capability slot maps an endpoint type to a model and optional overrides.
struct CapabilitySlot: Codable, Identifiable, Hashable {
    let id: UUID
    var endpointType: EndpointType
    var modelOverride: String?
    var pathOverride: String?
    var channelIDOverride: UUID?
    
    init(
        id: UUID = UUID(),
        endpointType: EndpointType,
        modelOverride: String? = nil,
        pathOverride: String? = nil,
        channelIDOverride: UUID? = nil
    ) {
        self.id = id
        self.endpointType = endpointType
        self.modelOverride = modelOverride
        self.pathOverride = pathOverride
        self.channelIDOverride = channelIDOverride
    }
}

/// The complete gateway configuration.
struct GatewayConfiguration: Codable {
    var channels: [ProviderChannel]
    var defaultChannelID: UUID?
    var capabilitySlots: [CapabilitySlot]
    
    /// Returns the default channel, or the first enabled channel sorted by priority.
    var activeChannel: ProviderChannel? {
        if let id = defaultChannelID, let channel = channels.first(where: { $0.id == id && $0.enabled }) {
            return channel
        }
        return channels.filter(\.enabled).sorted { $0.priority > $1.priority }.first
    }
    
    /// Returns the channel to use for a specific capability, respecting overrides.
    func channel(for endpointType: EndpointType) -> ProviderChannel? {
        if let slot = capabilitySlots.first(where: { $0.endpointType == endpointType }),
           let overrideID = slot.channelIDOverride,
           let channel = channels.first(where: { $0.id == overrideID && $0.enabled }) {
            return channel
        }
        return activeChannel
    }
    
    /// Returns the model to use for a specific capability.
    func model(for endpointType: EndpointType) -> String? {
        capabilitySlots.first(where: { $0.endpointType == endpointType })?.modelOverride
    }
    
    /// Returns the path to use for a specific capability.
    func path(for endpointType: EndpointType) -> String {
        capabilitySlots.first(where: { $0.endpointType == endpointType })?.pathOverride
            ?? endpointType.defaultPath
    }
}

/// The resolved request details for one call: the channel, key and path the client needs, read together on
/// the main actor so a caller gets one consistent snapshot.
struct GatewayRequestPlan {
    let baseURL: URL
    let apiKey: String
    let path: String
    let timeout: TimeInterval
    let proxy: URL?
}

/// Manages the gateway configuration, persisted to UserDefaults.
@MainActor
final class GatewayConfigurationStore: ObservableObject {
    static let shared = GatewayConfigurationStore()
    
    @Published var configuration: GatewayConfiguration {
        didSet { save() }
    }
    
    private let key = "gateway.configuration"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let config = try? JSONDecoder().decode(GatewayConfiguration.self, from: data) {
            self.configuration = config
        } else {
            // Default configuration with AIPDD built-in
            let aipddID = UUID()
            self.configuration = GatewayConfiguration(
                channels: [
                    ProviderChannel(
                        id: aipddID,
                        name: "AIPDD",
                        baseURL: URL(string: "https://api.aipdd.work")!,
                        enabled: true,
                        priority: 100,  // Highest priority
                        weight: 10,
                        timeout: 60,
                        isBuiltIn: true
                    )
                ],
                defaultChannelID: aipddID,
                capabilitySlots: EndpointType.allCases.map { endpoint in
                    CapabilitySlot(endpointType: endpoint)
                }
            )
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    /// Adds a new channel.
    func addChannel(_ channel: ProviderChannel) {
        configuration.channels.append(channel)
    }
    
    /// Updates an existing channel.
    func updateChannel(_ channel: ProviderChannel) {
        if let index = configuration.channels.firstIndex(where: { $0.id == channel.id }) {
            configuration.channels[index] = channel
        }
    }
    
    /// Deletes a channel (unless it's built-in).
    func deleteChannel(_ channelID: UUID) {
        guard let channel = configuration.channels.first(where: { $0.id == channelID }),
              !channel.isBuiltIn else { return }
        configuration.channels.removeAll { $0.id == channelID }
        // Clean up capability slot overrides
        for i in configuration.capabilitySlots.indices {
            if configuration.capabilitySlots[i].channelIDOverride == channelID {
                configuration.capabilitySlots[i].channelIDOverride = nil
            }
        }
        // Clear default if it was this channel
        if configuration.defaultChannelID == channelID {
            configuration.defaultChannelID = nil
        }
        // Delete the API key from Keychain
        try? KeychainStore.shared.delete(for: channelID)
    }
    
    /// Sets the default channel.
    func setDefaultChannel(_ channelID: UUID?) {
        configuration.defaultChannelID = channelID
    }
    
    /// Updates a capability slot.
    func updateSlot(_ slot: CapabilitySlot) {
        if let index = configuration.capabilitySlots.firstIndex(where: { $0.id == slot.id }) {
            configuration.capabilitySlots[index] = slot
        }
    }
    
    /// The model to use for a capability, respecting slot overrides.
    func model(for endpointType: EndpointType) -> String? {
        configuration.model(for: endpointType)
    }
    
    /// Resolves the channel, API key and path for an endpoint into a Sendable snapshot, so a background
    /// client can build its request without touching main-actor state.
    func plan(for endpointType: EndpointType) throws -> GatewayRequestPlan {
        let config = configuration
        guard let channel = config.channel(for: endpointType) else {
            throw GatewayClientError.noChannelAvailable
        }
        guard let apiKey = try KeychainStore.shared.retrieve(for: channel.id) else {
            throw GatewayClientError.missingAPIKey(channel.name)
        }
        return GatewayRequestPlan(baseURL: channel.baseURL, apiKey: apiKey,
                                  path: config.path(for: endpointType), timeout: channel.timeout, proxy: channel.proxy)
    }
}
