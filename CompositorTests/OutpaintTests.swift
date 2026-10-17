import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Outpainting without a network: the geometry that pads the picture and marks the fresh border, the exact
/// multipart the endpoint takes, and the session flow that grows the canvas and lands the answer — the sender
/// is stubbed so no request leaves the machine.
@MainActor
struct OutpaintTests {
    /// The single pixel at (x, y), read through an RGBA8 bitmap context.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = y * ctx.bytesPerRow + x * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    /// A flat blue image of the given size, standing in for the picture being extended.
    private func blue(_ width: Int, _ height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: Geometry

    @Test func paddedSizeGrowsByTwiceTheMargin() {
        let size = Outpaint.paddedSize(width: 100, height: 60, margin: 10)
        #expect(size == CGSize(width: 120, height: 80))
    }

    @Test func padDropsTheOriginalInTheMiddleOfABiggerBox() throws {
        let frame = try #require(Outpaint.pad(blue(8, 8), margin: 4))
        #expect(frame.width == 16 && frame.height == 16)
        let corner = pixel(frame, 0, 0)
        #expect(corner.a == 0, "the fresh border starts transparent")
        let center = pixel(frame, 8, 8) // inside the original, which sat at (4,4)…(11,11)
        #expect(center.a == 255 && center.b > 200, "the original rides in the middle")
    }

    @Test func maskIsWhiteOverTheBorderAndBlackOverTheOriginal() throws {
        let mask = try #require(Outpaint.mask(originalSize: CGSize(width: 8, height: 8), margin: 4))
        #expect(mask.width == 16 && mask.height == 16)
        #expect(pixel(mask, 0, 0).r > 247, "the border is white: paint here")
        #expect(pixel(mask, 8, 8).r < 8, "the original is black: leave it")
    }

    @Test func aZeroMarginMaskIsRefused() {
        #expect(Outpaint.mask(originalSize: CGSize(width: 8, height: 8), margin: 0) == nil)
    }

    // MARK: Wire format

    @Test func partsCarryPaddedImageBorderMaskPromptAndModel() {
        let parts = Outpaint.multipartParts(paddedImage: blue(8, 8), mask: blue(8, 8),
                                            prompt: "a misty forest", model: "test-model")
        let text = String(data: GatewayClient.buildMultipartBody(parts: parts, boundary: "BOUND"),
                          encoding: .isoLatin1) ?? ""
        #expect(text.contains("name=\"image\"; filename=\"image.png\""), "the padded picture travels as a PNG file")
        #expect(text.contains("name=\"mask\"; filename=\"image.png\""), "the border mask travels too")
        #expect(text.contains("name=\"prompt\"\r\n\r\na misty forest\r\n"), "the prompt is what to paint")
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

    @Test func outpaintGrowsTheCanvasAndLandsTheAnswer() async throws {
        let session = session(100, 100)
        let before = session.document?.layers.count ?? 0
        var sawPadded = CGSize.zero
        var sawMask = CGSize.zero
        let ok = await session.outpaint(margin: 10, prompt: "extend", model: "test-model") { padded, mask in
            sawPadded = CGSize(width: padded.width, height: padded.height)
            sawMask = CGSize(width: mask.width, height: mask.height)
            return blue(120, 120) // the painted enlarged canvas
        }
        #expect(ok)
        #expect(sawPadded == CGSize(width: 120, height: 120), "the padded canvas is sent, not the original")
        #expect(sawMask == CGSize(width: 120, height: 120), "the border mask matches the padded size")
        #expect(session.document?.width == 120 && session.document?.height == 120, "the canvas grew by twice the margin")
        #expect((session.document?.layers.count ?? 0) == before + 1, "the answer landed as a new layer")
        #expect(session.document?.layers.last?.asset?.image.width == 120)
    }

    @Test func outpaintRefusesAnEmptyPromptOrMargin() async {
        let session = session()
        var called = false
        let sender: (CGImage, CGImage) async throws -> CGImage = { _, _ in called = true; return blue(2, 2) }
        #expect(!(await session.outpaint(margin: 10, prompt: "", model: "m", sender: sender)))
        #expect(!(await session.outpaint(margin: 0, prompt: "x", model: "m", sender: sender)))
        #expect(!called, "a refused call never reaches the gateway")
    }

    @Test func outpaintStaysQuietWhenTheRequestFails() async {
        struct Boom: Error {}
        let session = session()
        let ok = await session.outpaint(margin: 10, prompt: "x", model: "m") { _, _ in throw Boom() }
        #expect(!ok)
        #expect(session.document?.width == 100, "a failed request leaves the canvas as it was")
    }

    @Test func outpaintNeedsADocument() async {
        let session = EditorSession()
        let ok = await session.outpaint(margin: 10, prompt: "x", model: "m") { _, _ in blue(2, 2) }
        #expect(!ok, "with no canvas there is nothing to extend")
    }

    // MARK: Catalogs

    private var sheetKeys: [String] {
        [
            "Extend Image…",
            "Outpaint",
            "Margin",
            "Grow the canvas and let the model paint only the new edges. The picture itself stays as it is.",
            "Extend",
            "Couldn't extend the image. Check the prompt and try again.",
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
