import Foundation

/// Represents an editing intent parsed from natural language.
struct EditingIntent: Codable {
    enum Action: String, Codable {
        case adjustLevels
        case adjustCurves
        case adjustHueSaturation
        case adjustExposure
        case adjustColorBalance
        case addAdjustmentLayer
        case removeAdjustmentLayer
        case reorderLayers
        case addMask
        case removeMask
        case invertMask
        case groupLayers
        case ungroupLayers
        case duplicateLayer
        case deleteLayer
        case renameLayer
        case changeBlendMode
        case changeOpacity
        case transformLayer
        case flipLayer
        case cropCanvas
        case resizeCanvas
        case rotateCanvas
        case flipCanvas
        case applyFilter
        case selectSubject
        case selectColorRange
        case invertSelection
        case expandSelection
        case contractSelection
        case featherSelection
        case deselect
        case fillSelection
        case strokeSelection
        case unknown
    }
    
    let action: Action
    let parameters: [String: AnyCodable]
    let targetLayerIDs: [String]?
    let requiresConfirmation: Bool
    let description: String
    
    init(
        action: Action,
        parameters: [String: AnyCodable] = [:],
        targetLayerIDs: [String]? = nil,
        requiresConfirmation: Bool = false,
        description: String = ""
    ) {
        self.action = action
        self.parameters = parameters
        self.targetLayerIDs = targetLayerIDs
        self.requiresConfirmation = requiresConfirmation
        self.description = description
    }
    
    private enum CodingKeys: String, CodingKey {
        case action, parameters, targetLayerIDs, requiresConfirmation, description
    }
    
    /// Lenient decoding: a model that omits `parameters`, `description` or `requiresConfirmation` still yields a
    /// usable intent instead of throwing (which would drop the whole response to the keyword fallback).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        parameters = (try? container.decode([String: AnyCodable].self, forKey: .parameters)) ?? [:]
        targetLayerIDs = try? container.decode([String].self, forKey: .targetLayerIDs)
        requiresConfirmation = (try? container.decode(Bool.self, forKey: .requiresConfirmation)) ?? false
        description = (try? container.decode(String.self, forKey: .description)) ?? ""
    }

    /// Actions that discard pixels or layers, so they must be confirmed no matter what the model says.
    /// The model's `requiresConfirmation` is untrusted input and defaults to false when omitted or
    /// malformed (see the lenient decoder above); a destructive action must never slip through by that
    /// accident, so the client hard-codes the lossy set and ORs it into the confirmation gate.
    nonisolated var isDestructive: Bool {
        switch action {
        case .deleteLayer, .removeMask, .removeAdjustmentLayer, .ungroupLayers, .cropCanvas:
            return true
        default:
            return false
        }
    }
}

/// Recognizes editing intents from natural language input. Runs on the main actor: it reads the
/// main-actor gateway configuration and hands the parsed intent straight to the editor.
@MainActor
final class IntentRecognition {
    static let shared = IntentRecognition()
    
    private init() {}
    
    /// Analyzes natural language input and returns an editing intent.
    func recognize(input: String, context: EditingContext) async throws -> EditingIntent {
        let systemPrompt = """
        You are an image editing assistant. Analyze the user's request and determine what editing action they want to perform.
        
        Available actions:
        - adjustLevels: Adjust levels (shadows, midtones, highlights)
        - adjustCurves: Adjust curves (tone curve)
        - adjustHueSaturation: Adjust hue, saturation, lightness
        - adjustExposure: Adjust exposure/brightness
        - adjustColorBalance: Adjust color balance (shadows, midtones, highlights)
        - addAdjustmentLayer: Add an adjustment layer
        - reorderLayers: Change layer order
        - addMask: Add a layer mask
        - removeMask: Remove a layer mask
        - groupLayers: Group selected layers
        - ungroupLayers: Ungroup layers
        - duplicateLayer: Duplicate a layer
        - deleteLayer: Delete a layer
        - renameLayer: Rename a layer
        - changeBlendMode: Change layer blend mode
        - changeOpacity: Change layer opacity
        - transformLayer: Transform (scale, rotate, move) a layer
        - flipLayer: Flip a layer horizontally or vertically
        - cropCanvas: Crop the canvas
        - resizeCanvas: Resize the canvas
        - rotateCanvas: Rotate the canvas
        - flipCanvas: Flip the canvas
        - applyFilter: Apply a filter (blur, sharpen, etc.)
        - selectSubject: Select the main subject
        - selectColorRange: Select by color range
        - invertSelection: Invert selection
        - expandSelection: Expand selection
        - contractSelection: Contract selection
        - featherSelection: Feather selection edges
        - deselect: Deselect all
        - fillSelection: Fill selection with color
        - strokeSelection: Stroke selection border
        
        Parameter keys per action (numbers unless noted):
        - adjustLevels: black/white (0–255), gamma; shadows/highlights also accepted
        - adjustCurves: points, an array of [x, y] pairs in 0–255
        - adjustHueSaturation: hue (−180…180), saturation, lightness (−100…100)
        - adjustExposure: exposure (−20…20), offset (−0.5…0.5), gamma (0.01…9.99)
        - adjustColorBalance: warmth or tint (−100…100), or shadow/mid/highlight CyanRed, MagentaGreen, YellowBlue
        - addAdjustmentLayer: kind ("Levels", "Curves", "Exposure", …)
        - changeBlendMode: mode ("Multiply", "Screen", …); changeOpacity: opacity (0–100)
        - reorderLayers: to ("up", "down", "front", "back")
        - transformLayer: dx, dy (pixels), scale (multiplier), rotation (degrees)
        - flipLayer: axis ("horizontal" or "vertical"); flipCanvas: axis; rotateCanvas: direction ("clockwise" or "counterclockwise")
        - cropCanvas: x, y, width, height in pixels; resizeCanvas: width, height in pixels
        - expandSelection/contractSelection/featherSelection: amount in pixels
        - fillSelection: with ("foreground" or "background"); renameLayer: name (text)
        - applyFilter: name (e.g. "Gaussian Blur"), radius
        
        Respond with a JSON object containing:
        - action: one of the actions above
        - parameters: object with action-specific parameters
        - targetLayerIDs: array of layer IDs to target (if applicable)
        - requiresConfirmation: true if the action is destructive (delete, merge, etc.)
        - description: brief description of what will happen
        
        Current context:
        - Active layer: \(context.activeLayerName ?? "none")
        - Has selection: \(context.hasSelection)
        - Layer count: \(context.layerCount)
        """
        
        let messages: [ChatCompletionRequest.ChatMessage] = [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: input)
        ]
        
        let request = ChatCompletionRequest(
            model: GatewayConfigurationStore.shared.model(for: .chat) ?? "gpt-4",
            messages: messages,
            temperature: 0.3
        )
        
        let response: ChatCompletionResponse = try await GatewayClient.shared.request(
            endpoint: .chat,
            body: request,
            as: ChatCompletionResponse.self
        )
        
        guard let content = response.choices.first?.message.content else {
            throw IntentRecognitionError.noResponse
        }
        
        // Parse the JSON response
        guard let data = content.data(using: .utf8),
              let intent = try? JSONDecoder().decode(EditingIntent.self, from: data) else {
            // Fallback: try to extract action from text
            return parseFallback(content)
        }
        
        return intent
    }
    
    /// Fallback parser for when JSON parsing fails. Kept internal so the keyword mapping is unit-testable
    /// without a live gateway.
    func parseFallback(_ text: String) -> EditingIntent {
        let lower = text.lowercased()
        
        if lower.contains("level") {
            return EditingIntent(action: .adjustLevels, description: "Adjust levels")
        } else if lower.contains("curve") {
            return EditingIntent(action: .adjustCurves, description: "Adjust curves")
        } else if lower.contains("hue") || lower.contains("saturation") {
            return EditingIntent(action: .adjustHueSaturation, description: "Adjust hue/saturation")
        } else if lower.contains("exposure") || lower.contains("brightness") {
            return EditingIntent(action: .adjustExposure, description: "Adjust exposure")
        } else if lower.contains("color balance") {
            return EditingIntent(action: .adjustColorBalance, description: "Adjust color balance")
        } else if lower.contains("deselect") {
            // Checked before "select ... subject": "deselect" itself contains "select", so the subject
            // branch would otherwise swallow "deselect the subject".
            return EditingIntent(action: .deselect, description: "Deselect all")
        } else if lower.contains("select") && lower.contains("subject") {
            return EditingIntent(action: .selectSubject, description: "Select subject")
        } else if lower.contains("invert") && lower.contains("selection") {
            return EditingIntent(action: .invertSelection, description: "Invert selection")
        } else if lower.contains("delete") && lower.contains("layer") {
            return EditingIntent(action: .deleteLayer, requiresConfirmation: true, description: "Delete layer")
        } else if lower.contains("duplicate") && lower.contains("layer") {
            return EditingIntent(action: .duplicateLayer, description: "Duplicate layer")
        } else if lower.contains("ungroup") {
            // Before "group": "ungroup" contains "group", so the group branch would otherwise win.
            return EditingIntent(action: .ungroupLayers, description: "Ungroup layers")
        } else if lower.contains("group") {
            return EditingIntent(action: .groupLayers, description: "Group layers")
        }
        
        return EditingIntent(action: .unknown, description: text)
    }
}

/// Context about the current editing state.
struct EditingContext {
    let activeLayerName: String?
    let hasSelection: Bool
    let layerCount: Int
}

enum IntentRecognitionError: Error, LocalizedError {
    case noResponse
    case parseFailed
    
    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "No response from AI"
        case .parseFailed:
            return "Failed to parse AI response"
        }
    }
}
