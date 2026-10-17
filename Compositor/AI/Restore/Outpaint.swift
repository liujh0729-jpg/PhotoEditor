import CoreGraphics
import Foundation

/// Outpainting: grow the canvas, keep the picture where it sits, and let the gateway paint only the new ring.
/// The endpoint needs two things and this builds both — a padded picture with the original dropped into the
/// middle of the bigger box, and a mask that's white over the fresh border (paint here) and black over the
/// original (leave it be). The request itself is the Retouch panel's pipeline, so it lands on a layer through
/// the session's own edits and folds into history like any other change.
enum Outpaint {
    /// The enlarged canvas: the original plus `margin` on every side.
    static func paddedSize(width: Int, height: Int, margin: Int) -> CGSize {
        CGSize(width: width + 2 * margin, height: height + 2 * margin)
    }

    /// The original dropped into the middle of the bigger, transparent box. nil if the box can't be built.
    static func pad(_ image: CGImage, margin: Int) -> CGImage? {
        guard margin >= 0, image.width > 0, image.height > 0,
              let context = CGContext(data: nil,
                                      width: image.width + 2 * margin,
                                      height: image.height + 2 * margin,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: CGFloat(margin), y: CGFloat(margin),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    /// White over the new border, black over where the original sits: the area the model is told to paint.
    static func mask(originalSize: CGSize, margin: Int) -> CGImage? {
        let width = Int(originalSize.width) + 2 * margin
        let height = Int(originalSize.height) + 2 * margin
        guard margin > 0, width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1) // Paint the whole box…
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(gray: 0, alpha: 1) // …then black out the original, which stays as it is.
        context.fill(CGRect(x: CGFloat(margin), y: CGFloat(margin), width: originalSize.width, height: originalSize.height))
        return context.makeImage()
    }

    /// The form fields the endpoint takes: the padded picture, the border mask, the prompt, the slot model.
    static func multipartParts(paddedImage: CGImage, mask: CGImage, prompt: String, model: String) -> [MultipartPart] {
        var parts: [MultipartPart] = []
        if let image = ImageBridge.multipartPart(for: paddedImage, name: "image") { parts.append(image) }
        if let mask = ImageBridge.multipartPart(for: mask, name: "mask") { parts.append(mask) }
        parts.append(.text("prompt", prompt))
        parts.append(.text("model", model))
        parts.append(.text("n", "1"))
        parts.append(.text("response_format", "b64_json"))
        return parts
    }
}
