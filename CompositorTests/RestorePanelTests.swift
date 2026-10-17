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
            let generation = preset.id == "superResolution" || preset.id == "hdRestore" || preset.id == "aiBackground"
            #expect(preset.endpointSlot == (generation ? .imageGeneration : .imageEdits),
                    "only the upscale family and the background generation run on the generation slot")
            #expect(preset.subjectCompositing == (preset.id == "aiBackground"),
                    "the background generation is the one preset that composites locally")
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
            "Apply to all layers",
            "Couldn't retouch: %@.",
            "The subject cutout runs on one layer at a time.",
            "Run this preset on every pixel layer, one after another.",
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

    // MARK: Batch ("Apply to all layers")

    private struct StubError: Error {}

    private func items(_ names: [String]) -> [RestoreBatchItem] {
        names.enumerated().map { RestoreBatchItem(layerID: UUID(), name: $0.element,
                                                   image: swatch(4 + $0.offset, 3)) }
    }

    @Test func batchRunsEveryLayerOnceWithTheSamePreset() async {
        let preset = RestorePresets.all.first { $0.id == "removeNoise" }!
        let rows = items(["A", "B", "C"])
        var calls = 0
        var seen: [UUID] = []
        let outcome = await RestoreBatch.run(items: rows, preset: preset, model: "test-model") { item, _, _ in
            calls += 1
            seen.append(item.layerID)
            return swatch(2, 2)
        }
        #expect(calls == rows.count, "N layers, N requests")
        #expect(seen == rows.map(\.layerID), "one pass per layer, in order")
        #expect(outcome.retouched.count == 3 && outcome.failed.isEmpty)
    }

    @Test func batchSkipsFailedLayersWithoutStopping() async {
        let preset = RestorePresets.all.first { $0.id == "removeWatermark" }!
        let rows = items(["A", "B", "C", "D"])
        var calls = 0
        let outcome = await RestoreBatch.run(items: rows, preset: preset, model: "test-model") { item, _, _ in
            calls += 1
            if item.name == "B" { throw StubError() }
            return swatch(2, 2)
        }
        #expect(calls == 4, "a failing layer doesn't cut the run short")
        #expect(outcome.retouched.count == 3)
        #expect(outcome.failed.map(\.name) == ["B"], "the layer the gateway let down is listed by name")
        #expect(outcome.failureSummary == "B")
    }

    @Test func batchLandsOnTheLayersInOneHistoryEntry() async throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        session.insert(ImportedImage(image: swatch(200, 200), thumbnail: swatch(20, 20), name: "A"))
        session.insert(ImportedImage(image: swatch(120, 90), thumbnail: swatch(20, 20), name: "B"))
        let layers = session.document?.layers ?? []
        #expect(layers.count == 2)
        let results = [(layerID: layers[0].id, image: swatch(50, 40)),
                       (layerID: layers[1].id, image: swatch(60, 20))]
        let changed = session.applyRestoreBatch(results, actionName: "Remove Noise")
        #expect(changed == 2)
        #expect(session.document?.layers[0].asset?.image.width == 50)
        #expect(session.document?.layers[1].transform.size == CGSize(width: 60, height: 20))
        // The whole batch is a single step: one undo takes both layers back.
        #expect(session.history.undoName == "Remove Noise")
        session.undo()
        #expect(session.document?.layers[0].asset?.image.width == 200)
        #expect(session.document?.layers[1].asset?.image.width == 120)
    }

    @Test func batchIgnoresLayersThatCannotTakeThePixels() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        session.insert(ImportedImage(image: swatch(100, 100), thumbnail: swatch(20, 20), name: "A"))
        let changed = session.applyRestoreBatch([(layerID: UUID(), image: swatch(10, 10))], actionName: "Remove Noise")
        #expect(changed == 0, "an id that isn't on the canvas changes nothing")
        #expect(session.history.undoName != "Remove Noise", "nothing was recorded")
    }

    // MARK: Background generation ("AI Background")

    /// A flat gray mask swatch, `level` from black to white.
    private func graySwatch(_ level: CGFloat, _ width: Int = 4, _ height: Int = 3) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: level, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The single pixel at (x, y), through an RGBA8 bitmap context.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = y * ctx.bytesPerRow + x * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    @Test func invertFlipsTheCutout() {
        let white = RestoreSheet.invert(graySwatch(1))
        #expect(pixel(white, 0, 0).r < 8, "white in, black out")
        let black = RestoreSheet.invert(graySwatch(0))
        #expect(pixel(black, 0, 0).r > 247, "black in, white out")
    }

    @Test func compositeKeepsTheSubjectOverTheAnswer() throws {
        // back: left half white ("paint here"), right half black (the subject stays).
        let backContext = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        backContext.setFillColor(gray: 1, alpha: 1)
        backContext.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        let back = backContext.makeImage()!
        let subject = swatch(4, 3)  // the blue swatch: what Vision said was the subject
        let generated = RestorePanelTests_flatRed(4, 3)
        let out = try RestoreSheet.composite(subject: subject, over: generated, back: back)
        let left = pixel(out, 0, 0)
        #expect(left.r > 200 && left.g < 60, "over the painted area the answer shows through")
        let right = pixel(out, 3, 0)
        #expect(right.b > 200 && right.r < 60, "over the subject the layer's own pixels stay on top")
    }

    @Test func compositeWithoutAMaskIsTheSubjectAlone() throws {
        let out = try RestoreSheet.composite(subject: swatch(4, 3), over: swatch(9, 7), back: nil)
        #expect(out.width == 4 && out.height == 3)
    }
}

/// A flat red swatch for the compositing tests.
private func RestorePanelTests_flatRed(_ width: Int, _ height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
