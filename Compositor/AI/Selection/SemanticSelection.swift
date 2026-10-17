import AppKit
import CoreImage
import Vision

/// The semantic selector's on-device pass: Vision's foreground subjects stepped out as a hard mask at the panel's
/// threshold. No pixels leave the Mac; the prompt only names the edit the mask becomes.
nonisolated enum SemanticSelection {
    enum Failure: LocalizedError {
        case noSubject
        var errorDescription: String? { "No foreground subject was detected in this picture. Try an image with a more distinct subject." }
    }

    /// A white-on-black mask of `image`'s foreground subjects, at its size. Where the model's edge is a gray,
    /// `threshold` decides which side that pixel lands on.
    static func subjectMask(in image: CGImage, threshold: Double) throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let mask = try PixelAdjust.render(CIImage(cvPixelBuffer: buffer), width: image.width, height: image.height, isMask: true)
        return try cut(mask, threshold: threshold)
    }

    /// A hard step at `threshold`: a hairline band and a scale-up turn grays above it into white, everything below into black.
    static func cut(_ mask: CGImage, threshold: Double) throws -> CGImage {
        let level = min(0.999, max(0.001, threshold))
        let scale = 1 / 0.001
        let image = CIImage(cgImage: mask).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: level, y: level, z: level, w: 0),
            "inputMaxComponents": CIVector(x: level + 0.001, y: level + 0.001, z: level + 0.001, w: 1),
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputBiasVector": CIVector(x: -level * scale, y: -level * scale, z: -level * scale, w: 0),
        ])
        return try PixelAdjust.render(image, width: mask.width, height: mask.height, isMask: true)
    }
}
