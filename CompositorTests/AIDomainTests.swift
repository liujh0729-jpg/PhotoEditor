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
        #expect(recognizer.parseFallback("deselect the subject").action == .deselect, "'deselect' outranks 'select the subject'")
        #expect(recognizer.parseFallback("ungroup the layers").action == .ungroupLayers, "'ungroup' is checked before 'group'")
        #expect(recognizer.parseFallback("group these layers").action == .groupLayers)
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

    @Test func editingIntentDecodesLenientlyWhenFieldsAreMissing() throws {
        // A chat model that omits parameters / targetLayerIDs / requiresConfirmation / description still decodes
        // to a usable intent instead of throwing and dropping to the keyword fallback.
        let json = #"{"action":"deselect"}"#
        let intent = try JSONDecoder().decode(EditingIntent.self, from: Data(json.utf8))
        #expect(intent.action == .deselect)
        #expect(intent.parameters.isEmpty)
        #expect(intent.targetLayerIDs == nil)
        #expect(!intent.requiresConfirmation)
        #expect(intent.description.isEmpty)
    }

    // MARK: Multipart body assembly

    @Test func multipartBodyMatchesWireFormat() {
        // The off-main-actor builder keeps the exact same wire format as the previous inline loop: fields
        // separated by the boundary, binary parts carry Content-Disposition + Content-Type, terminator is
        // "--<boundary>--".
        let bytes = Data([0x00, 0x01, 0x02])
        let parts: [MultipartPart] = [
            .text("prompt", "sunny sky"),
            .data("image", bytes, filename: "a.png", mimeType: "image/png"),
        ]
        let body = GatewayClient.buildMultipartBody(parts: parts, boundary: "BOUND")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--BOUND\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"prompt\"\r\n\r\nsunny sky\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"image\"; filename=\"a.png\"\r\n"))
        #expect(text.contains("Content-Type: image/png\r\n\r\n"))
        #expect(text.hasSuffix("--BOUND--\r\n"))
        #expect(body.range(of: bytes) != nil, "the raw bytes are spliced in, not base64-encoded")
    }

    // MARK: Speech-to-text Content-Type

    @Test func sttsPicksMIMEFromExtension() {
        // Whisper-style gateways key their decoder off the file part's Content-Type; a hard-coded "audio/mpeg"
        // would mislabel anything else.
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.mp3")) == "audio/mpeg")
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.wav")) == "audio/wav")
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.m4a")) == "audio/mp4")
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.flac")) == "audio/flac")
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.OGG")) == "audio/ogg", "case doesn't matter")
        #expect(STTSSheet.mimeType(for: URL(fileURLWithPath: "/x/clip.unknown")) == "application/octet-stream")
    }

    // MARK: Gateway error decoding

    @Test func gatewayErrorToleratesNumericAndStringCodes() throws {
        // The `code` field is string on OpenAI but numeric on some proxies; either way the message must survive.
        let asString = #"{"error":{"message":"rate limited","type":"rate_limit","code":"429"}}"#
        let asNumber = #"{"error":{"message":"rate limited","type":"rate_limit","code":429}}"#
        struct Wrapper: Decodable { let error: GatewayError }
        let a = try JSONDecoder().decode(Wrapper.self, from: Data(asString.utf8)).error
        let b = try JSONDecoder().decode(Wrapper.self, from: Data(asNumber.utf8)).error
        #expect(a.errorDescription == "rate limited")
        #expect(b.errorDescription == "rate limited")
    }

    // MARK: Privacy Mode

    /// The flag rides the saved config: it survives a round trip, and a config written before Privacy Mode
    /// existed decodes as the old, sending behavior rather than failing whole.
    @Test func privacyModeSurvivesTheSavedConfig() throws {
        let store = GatewayConfigurationStore.shared
        var on = store.configuration
        on.privacyMode = true
        let back = try JSONDecoder().decode(GatewayConfiguration.self, from: JSONEncoder().encode(on))
        #expect(back.privacyMode, "the flag rides the saved config")
        let old = #"{"channels":[{"id":"A1A1A1A1-B2B2-C3C3-D4D4-E5E5E5E5E5E5","name":"Test","baseURL":"https://example.invalid","enabled":true,"priority":0,"weight":10,"timeout":60,"isBuiltIn":false}],"capabilitySlots":[]}"#
        let before = try JSONDecoder().decode(GatewayConfiguration.self, from: Data(old.utf8))
        #expect(!before.privacyMode, "a config from before Privacy Mode meant the old, sending behavior")
    }

    /// With Privacy Mode on, every gateway call refuses before a request is built — and the catalog sync
    /// simply doesn't go out, rather than failing at a missing key.
    @Test func privacyModeRefusesEveryGatewayCall() async throws {
        let store = GatewayConfigurationStore.shared
        let was = store.privacyMode
        defer { store.privacyMode = was }
        store.privacyMode = true
        let channel = ProviderChannel(name: "Test", baseURL: URL(string: "https://example.invalid")!)
        await #expect(throws: GatewayClientError.privacyMode) {
            _ = try await GatewayClient.shared.request(endpoint: .chat, body: ["model": "gpt"], as: [String: String].self)
        }
        await #expect(throws: GatewayClientError.privacyMode) {
            _ = try await GatewayClient.shared.get(endpoint: .chat, path: "/v1/models", as: [String: String].self)
        }
        await #expect(throws: GatewayClientError.privacyMode) {
            _ = try await GatewayClient.shared.uploadMultipart(endpoint: .imageEdits, parts: [.text("prompt", "cat")], as: [String: String].self)
        }
        await #expect(throws: GatewayClientError.privacyMode) {
            _ = try await GatewayClient.shared.downloadBinary(endpoint: .audioSpeech, body: ["input": "hello"])
        }
        await #expect(throws: GatewayClientError.privacyMode) {
            _ = try await GatewayClient.shared.fetchRaw(channel: channel, apiKey: "sk-test", path: "/v1/models")
        }
        // Quietly skipping beats an error dialog: the catalog list just stays as the cache showed it.
        try await CatalogStore.shared.sync()
        // And the refusal tells the user where the switch is.
        #expect(GatewayClientError.privacyMode.errorDescription?.contains("Settings") == true)
        store.privacyMode = false
        do {
            // The unreachable host proves the call actually went out once Privacy Mode is off.
            _ = try await GatewayClient.shared.fetchRaw(channel: channel, apiKey: "sk-test", path: "/v1/models")
            Issue.record("an unreachable channel should fail, not answer")
        } catch GatewayClientError.privacyMode {
            Issue.record("Privacy Mode is off; the call should go out and fail on the network")
        } catch {}
    }
}
