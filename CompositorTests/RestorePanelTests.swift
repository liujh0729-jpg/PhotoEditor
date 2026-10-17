import Testing
import AppKit
@testable import Compositor

/// The AI Retouch & Enhance panel without a network: the shape of the preset table, whether every string it
/// shows is translated in all seven catalogs, the exact multipart wire format the presets produce, and how a
/// response becomes a CGImage.
@MainActor
struct RestorePanelTests {
    // MARK: Preset table

    @Test func presetTableIsWellFormed() {
        let ids = RestorePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count, "one id per preset")
        let titles = RestorePresets.all.map(\.title)
        #expect(Set(titles).count == titles.count, "titles double as catalog keys; two presets can't share one")
        for preset in RestorePresets.all {
            #expect(!preset.prompt.isEmpty, "\(preset.id) needs an instruction to send")
            #expect(!preset.symbol.isEmpty, "\(preset.id) needs a list icon")
            let upscales = preset.id == "superResolution" || preset.id == "hdRestore"
            #expect(preset.endpointSlot == (upscales ? .imageGeneration : .imageEdits),
                    "only the upscale family runs on the generation slot")
        }
        #expect(RestorePresets.all.count >= 30, "the panel promises a broad table")
    }

    // MARK: Catalogs

    /// The keys the panel itself renders, next to the preset titles.
    private var panelKeys: [String] {
        [
            "AI Retouch & Enhance…",
            "Retouching…",
            "Retouched",
            "No result yet",
            "Slot default",
            "No pixel layer to retouch. Select a layer first.",
            "The picture goes to the gateway model the slot names. A selection or an enabled mask limits what gets touched.",
            "Couldn't apply to the active layer. Select a pixel layer first.",
        ]
    }

    private func catalogKeys(forLocalization localization: String) throws -> Set<String> {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                 inDirectory: "\(localization).lproj"),
                                "\(localization) catalog ships with the app")
        // The build copies catalogs as UTF-16; the repo keeps them UTF-8. Read whichever this is.
        let text: String
        if let utf16 = try? String(contentsOfFile: path, encoding: .utf16), utf16.contains("=") {
            text = utf16
        } else {
            text = try String(contentsOfFile: path, encoding: .utf8)
        }
        var keys = Set<String>()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            keys.insert(String(key.dropFirst().dropLast()))
        }
        return keys
    }

    @Test func everyPresetTitleIsTranslated() throws {
        for localization in ["zh-Hans", "ja", "fr", "es", "ru", "vi", "ar"] {
            let keys = try catalogKeys(forLocalization: localization)
            for preset in RestorePresets.all {
                #expect(keys.contains(preset.title), "\(preset.title) missing from \(localization)")
            }
        }
    }

    @Test func panelStringsAreTranslated() throws {
        for localization in ["zh-Hans", "ja", "fr", "es", "ru", "vi", "ar"] {
            let keys = try catalogKeys(forLocalization: localization)
            for key in panelKeys {
                #expect(keys.contains(key), "\(key) missing from \(localization)")
            }
        }
    }

    // MARK: Wire format

    private func swatch(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func body(_ parts: [MultipartPart]) -> String {
        // The PNG bytes make the body invalid UTF-8; latin-1 maps every byte so the field markers stay readable.
        String(data: GatewayClient.buildMultipartBody(parts: parts, boundary: "BOUND"), encoding: .isoLatin1) ?? ""
    }

    @Test func editPartsCarryImagePromptAndSlotModel() {
        let preset = RestorePresets.all.first { $0.id == "removeWatermark" }!
        let text = body(RestoreSheet.multipartParts(image: swatch(8, 6), mask: nil, preset: preset,
                                                    model: "test-model"))
        #expect(text.contains("name=\"image\"; filename=\"image.png\""), "the layer's pixels travel as a PNG file")
        #expect(text.contains("name=\"prompt\"\r\n\r\n\(preset.prompt)\r\n"), "the preset's instruction is the prompt")
        #expect(text.contains("name=\"model\"\r\n\r\ntest-model\r\n"), "the resolved model goes through")
        #expect(text.contains("name=\"n\"\r\n\r\n1\r\n"), "one answer per request")
        #expect(text.contains("name=\"response_format\"\r\n\r\nb64_json\r\n"), "the sheet decodes base64, not URLs")
        #expect(!text.contains("name=\"mask\""), "no selection, no mask field")
    }

    @Test func maskTravelsWhenOneApplies() {
        let preset = RestorePresets.all.first { $0.id == "removeNoise" }!
        let text = body(RestoreSheet.multipartParts(image: swatch(8, 6), mask: swatch(8, 6), preset: preset,
                                                    model: "test-model"))
        #expect(text.contains("name=\"mask\"; filename=\"image.png\""), "the selection or layer mask limits the edit")
    }

    // MARK: Response decoding

    @Test func firstImageDecodesBase64() async throws {
        let source = swatch(4, 3)
        let base64 = try #require(ImageBridge.base64(from: source))
        let response = ImageResponse(data: [.init(url: nil, b64_json: base64, revised_prompt: nil)], created: nil)
        let image = try await RestoreSheet.firstImage(of: response)
        #expect(image.width == 4 && image.height == 3, "the round trip keeps the picture's size")
    }

    @Test func firstImageRejectsAnEmptyResponse() async {
        let response = ImageResponse(data: [], created: nil)
        do {
            _ = try await RestoreSheet.firstImage(of: response)
            Issue.record("an answer with no image must not pass")
        } catch {
            #expect((error as? GatewayClientError) == .invalidResponse)
        }
    }
}
