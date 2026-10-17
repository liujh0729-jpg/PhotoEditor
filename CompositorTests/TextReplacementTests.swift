import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Text replacement without a network: the mask that marks the words to lift off, the exact multipart the endpoint
/// takes, and the session flow that erases them in place and lays new text back over the same spot — the sender is
/// stubbed so no request leaves the machine.
@MainActor
struct TextReplacementTests {
    /// The single pixel at (x, y) of any image, read through an RGBA8 bitmap context (grayscale lands in R).
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = y * ctx.bytesPerRow + x * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    /// A flat blue image of the given size, standing in for the picture the words sit on.
    private func blue(_ width: Int, _ height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: Mask

    @Test func eraseMaskIsWhiteOverTheBoxAndBlackElsewhere() throws {
        let mask = try #require(TextReplacement.eraseMask(box: CGRect(x: 40, y: 40, width: 20, height: 20),
                                                          canvasSize: CGSize(width: 100, height: 100)))
        #expect(mask.width == 100 && mask.height == 100)
        #expect(pixel(mask, 50, 50).r > 247, "the box is white: erase here")
        #expect(pixel(mask, 5, 5).r < 8, "everything else is black: leave it")
    }

    @Test func eraseMaskRefusesAnEmptyBoxOrCanvas() {
        let canvas = CGSize(width: 100, height: 100)
        #expect(TextReplacement.eraseMask(box: .zero, canvasSize: canvas) == nil)
        #expect(TextReplacement.eraseMask(box: CGRect(x: 0, y: 0, width: 10, height: 0), canvasSize: canvas) == nil)
        #expect(TextReplacement.eraseMask(box: CGRect(x: 0, y: 0, width: 10, height: 10),
                                         canvasSize: .zero) == nil)
    }

    // MARK: Wire format

    @Test func partsCarryImageMaskErasePromptAndModel() {
        let parts = TextReplacement.multipartParts(image: blue(8, 8), mask: blue(8, 8), model: "test-model")
        let text = String(data: GatewayClient.buildMultipartBody(parts: parts, boundary: "BOUND"),
                          encoding: .isoLatin1) ?? ""
        #expect(text.contains("name=\"image\"; filename=\"image.png\""), "the picture travels as a PNG file")
        #expect(text.contains("name=\"mask\"; filename=\"image.png\""), "the erase mask travels too")
        #expect(text.contains("name=\"prompt\"\r\n\r\n\(TextReplacement.erasePrompt)\r\n"), "the model is told to remove the text")
        #expect(text.contains("name=\"model\"\r\n\r\ntest-model\r\n"), "the resolved model goes through")
        #expect(text.contains("name=\"response_format\"\r\n\r\nb64_json\r\n"), "the sheet decodes base64, not URLs")
    }

    // MARK: Session flow

    private func session(_ width: Int = 100, _ height: Int = 100) -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: width, height: height)
        session.insert(ImportedImage(image: blue(width, height), thumbnail: blue(20, 20), name: "Picture"))
        return session
    }

    @Test func replaceTextErasesInPlaceAndLaysNewTextBack() async throws {
        let session = session(100, 100)
        let before = session.document?.layers.count ?? 0
        var sawImage = CGSize.zero
        var sawMask = CGSize.zero
        let box = CGRect(x: 20, y: 30, width: 40, height: 16)
        let ok = await session.replaceText(in: box, newText: "New words", model: "test-model") { image, mask in
            sawImage = CGSize(width: image.width, height: image.height)
            sawMask = CGSize(width: mask.width, height: mask.height)
            return blue(100, 100) // the same picture with the old words painted out
        }
        #expect(ok)
        #expect(sawImage == CGSize(width: 100, height: 100), "the active layer's own pixels are sent")
        #expect(sawMask == CGSize(width: 100, height: 100), "the erase mask matches the layer's pixel grid")
        #expect((session.document?.layers.count ?? 0) == before + 1, "the new text lands as an extra layer")
        let textLayer = try #require(session.document?.layers.last(where: { $0.liveText != nil }))
        #expect(textLayer.liveText?.style.content == "New words", "the words that go back are the ones typed")
    }

    @Test func replaceTextRefusesEmptyWordsOrAnUnusableBox() async {
        let session = session()
        var called = false
        let sender: (CGImage, CGImage) async throws -> CGImage = { _, _ in called = true; return blue(2, 2) }
        #expect(!(await session.replaceText(in: CGRect(x: 10, y: 10, width: 20, height: 10),
                                            newText: "   ", model: "m", sender: sender)))
        #expect(!(await session.replaceText(in: .zero, newText: "x", model: "m", sender: sender)))
        #expect(!called, "a refused call never reaches the gateway")
        #expect(session.document?.layers.count == 1, "nothing was erased or added")
    }

    @Test func replaceTextStaysQuietWhenTheRequestFails() async {
        struct Boom: Error {}
        let session = session()
        let ok = await session.replaceText(in: CGRect(x: 10, y: 10, width: 20, height: 10),
                                           newText: "x", model: "m") { _, _ in throw Boom() }
        #expect(!ok)
        #expect(session.document?.layers.count == 1, "a failed request leaves the canvas as it was")
    }

    @Test func replaceTextNeedsADocument() async {
        let session = EditorSession()
        let ok = await session.replaceText(in: CGRect(x: 10, y: 10, width: 20, height: 10),
                                           newText: "x", model: "m") { _, _ in blue(2, 2) }
        #expect(!ok, "with no canvas there is nothing to replace")
    }

    // MARK: Catalogs

    private var sheetKeys: [String] {
        [
            "Replace Text…",
            "Replace Text",
            "New text",
            "Replace",
            "Select a layer with text on it first.",
            "Couldn't replace the text. Try again.",
        ]
    }

    private func catalogKeys(forLocalization localization: String) throws -> Set<String> {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                 inDirectory: "\(localization).lproj"))
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

    @Test func sheetStringsAreTranslated() throws {
        for localization in ["zh-Hans", "ja", "fr", "es", "ru", "vi", "ar"] {
            let keys = try catalogKeys(forLocalization: localization)
            for key in sheetKeys {
                #expect(keys.contains(key), "\(key) missing from \(localization)")
            }
        }
    }
}
