import Foundation
import Testing
@testable import Compositor

/// The pure, gateway-free logic of the AI layer: the keyword fallback that reads an intent out of loose text,
/// the `AnyCodable` box that carries arbitrary JSON parameters, and how those decode into an `EditingIntent`.
@MainActor
struct AIDomainTests {
    // MARK: Natural-language fallback parsing

    @Test func fallbackMapsKeywordsToActions() {
        let recognizer = IntentRecognition.shared
        #expect(recognizer.parseFallback("make the levels better").action == .adjustLevels)
        #expect(recognizer.parseFallback("Tone down the CURVES").action == .adjustCurves, "case doesn't matter")
        #expect(recognizer.parseFallback("boost the saturation").action == .adjustHueSaturation)
        #expect(recognizer.parseFallback("raise the exposure").action == .adjustExposure)
        #expect(recognizer.parseFallback("select the subject").action == .selectSubject)
        #expect(recognizer.parseFallback("deselect everything").action == .deselect, "'deselect' is checked before the plain 'select' path")
        #expect(recognizer.parseFallback("invert the selection").action == .invertSelection)
    }

    @Test func fallbackFlagsDestructiveActionsForConfirmation() {
        let recognizer = IntentRecognition.shared
        let delete = recognizer.parseFallback("delete this layer")
        #expect(delete.action == .deleteLayer)
        #expect(delete.requiresConfirmation, "deleting a layer is destructive")
        #expect(!recognizer.parseFallback("duplicate the layer").requiresConfirmation)
    }

    @Test func fallbackFallsThroughToUnknown() {
        let intent = IntentRecognition.shared.parseFallback("tell me a joke")
        #expect(intent.action == .unknown)
        #expect(intent.description == "tell me a joke", "the leftover text is kept as the description")
    }

    // MARK: AnyCodable

    private func roundTrip(_ value: Any) throws -> Any {
        // Wrapped in a dictionary so the JSON stays a container rather than a bare top-level fragment.
        let data = try JSONEncoder().encode(["v": AnyCodable(value)])
        return try JSONDecoder().decode([String: AnyCodable].self, from: data)["v"]!.value
    }

    @Test func anyCodableRoundTripsScalars() throws {
        #expect(try roundTrip(42) as? Int == 42)
        #expect(try roundTrip("hello") as? String == "hello")
        #expect(try roundTrip(true) as? Bool == true)
        #expect(try roundTrip(1.5) as? Double == 1.5)
    }

    @Test func anyCodableRoundTripsNestedContainers() throws {
        let dict = try roundTrip(["count": 3, "label": "sky"]) as? [String: Any]
        #expect(dict?["count"] as? Int == 3)
        #expect(dict?["label"] as? String == "sky")
        let array = try roundTrip([1, 2, 3]) as? [Any]
        #expect(array?.count == 3 && array?[0] as? Int == 1)
    }

    // MARK: EditingIntent decoding

    @Test func editingIntentDecodesParameters() throws {
        let json = #"{"action":"renameLayer","parameters":{"name":"Sky"},"targetLayerIDs":null,"requiresConfirmation":false,"description":"Rename layer"}"#
        let intent = try JSONDecoder().decode(EditingIntent.self, from: Data(json.utf8))
        #expect(intent.action == .renameLayer)
        #expect(intent.parameters["name"]?.value as? String == "Sky")
        #expect(intent.targetLayerIDs == nil)
        #expect(!intent.requiresConfirmation)
    }

    @Test func editingIntentEncodingRoundTripsAParameter() throws {
        let intent = EditingIntent(action: .renameLayer, parameters: ["name": AnyCodable("Ground")], description: "Rename")
        let decoded = try JSONDecoder().decode(EditingIntent.self, from: try JSONEncoder().encode(intent))
        #expect(decoded.action == .renameLayer)
        #expect(decoded.parameters["name"]?.value as? String == "Ground")
    }
}
