import CoreGraphics
import Foundation

/// Text replacement: lift the words a picture already carries off it, so the artist can put new ones back in the
/// same place. The endpoint is the Retouch panel's own inpainting pipeline — the same picture back with only the
/// masked box repainted — so this builds that box's mask (white over the words to erase, black everywhere else)
/// and the request fields. The new text lands through the Type tool, so it folds into history like words typed
/// by hand.
enum TextReplacement {
    /// What the model is told to do with the masked box: take the text out, keep everything around it.
    static let erasePrompt = "Remove the text inside the marked area and reconstruct the background behind it seamlessly."

    /// White over `box`, black over the rest, at the picture's own resolution: the area the model is told to repaint.
    /// nil if the box or the canvas can't be drawn.
    static func eraseMask(box: CGRect, canvasSize: CGSize) -> CGImage? {
        let width = Int(canvasSize.width), height = Int(canvasSize.height)
        guard width > 0, height > 0,
              !box.isNull, !box.isInfinite, box.width > 0, box.height > 0,
              box.origin.x.isFinite, box.origin.y.isFinite, box.width.isFinite, box.height.isFinite,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1) // Leave the whole picture as it is…
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(gray: 1, alpha: 1) // …and mark only the words to erase.
        context.fill(box)
        return context.makeImage()
    }

    /// The form fields the endpoint takes: the picture, the erase mask, the fixed prompt, the slot model.
    static func multipartParts(image: CGImage, mask: CGImage, model: String) -> [MultipartPart] {
        var parts: [MultipartPart] = []
        if let image = ImageBridge.multipartPart(for: image, name: "image") { parts.append(image) }
        if let mask = ImageBridge.multipartPart(for: mask, name: "mask") { parts.append(mask) }
        parts.append(.text("prompt", erasePrompt))
        parts.append(.text("model", model))
        parts.append(.text("n", "1"))
        parts.append(.text("response_format", "b64_json"))
        return parts
    }
}
