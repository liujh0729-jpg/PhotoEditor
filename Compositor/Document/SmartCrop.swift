import CoreImage
import Vision

/// Auto Crop's composition pick. Vision's objectness saliency says where the picture's subject is; the suggested
/// box keeps the subject with breathing room, clamped to the canvas, with edges that fall near a thirds line or
/// the border snapping onto it — the way crop edges snap, but aimed at composition rather than at existing layers.
/// All of it runs on this Mac, so it keeps working in Privacy Mode.
nonisolated enum SmartCrop {
    /// The crop to suggest for `image`, or nil when there is no subject to compose around — a flat or purely
    /// noisy picture reads as "everything is the subject", which leaves nothing to crop.
    static func suggestRect(in image: CGImage) async -> CGRect? {
        await Task.detached(priority: .userInitiated) { () -> CGRect? in
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            let request = VNGenerateObjectnessBasedSaliencyImageRequest()
            do { try handler.perform([request]) } catch { return nil }
            guard let observation = request.results?.first else { return nil }
            let saliency: CGImage
            do {
                saliency = try PixelAdjust.render(CIImage(cvPixelBuffer: observation.pixelBuffer),
                                                  width: image.width, height: image.height, isMask: true)
            } catch { return nil }
            guard let levels = levels(of: saliency),
                  let subject = subjectBox(levels, width: image.width, height: image.height) else { return nil }
            return suggestRect(subject: subject, in: CGSize(width: image.width, height: image.height))
        }.value
    }

    /// The salient pixels' bounding box, top-left origin, or nil when they are missing or spread over the whole
    /// picture. `levels` is one byte per pixel, row 0 at the image's top edge.
    static func subjectBox(_ levels: [UInt8], width: Int, height: Int, threshold: Double = 0.5) -> CGRect? {
        guard levels.count == width * height, width > 0, height > 0 else { return nil }
        let cut = UInt8(max(1, min(254, Int(threshold * 255))))
        var minX = width, minY = height, maxX = -1, maxY = -1, count = 0
        for y in 0..<height {
            for x in 0..<width where levels[y * width + x] >= cut {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                count += 1
            }
        }
        guard maxX >= 0, count >= 4 else { return nil }
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard box.width * box.height < 0.95 * CGFloat(width * height) else { return nil }
        return box
    }

    /// A crop box around `subject`: a third of its own size as margin, clamped to the canvas, then each edge
    /// moved onto a nearby thirds line or border — within 6% of the canvas — as long as the subject stays inside.
    static func suggestRect(subject: CGRect, in size: CGSize) -> CGRect? {
        guard subject.width > 0, subject.height > 0, size.width > 1, size.height > 1 else { return nil }
        let full = CGRect(origin: .zero, size: size)
        let boxed = subject.insetBy(dx: -subject.width * 0.35, dy: -subject.height * 0.35).intersection(full)
        guard !boxed.isNull, boxed.width >= 2, boxed.height >= 2 else { return nil }
        let xs = [0, size.width / 3, 2 * size.width / 3, size.width]
        let ys = [0, size.height / 3, 2 * size.height / 3, size.height]
        let tolerance = CGSize(width: size.width * 0.06, height: size.height * 0.06)
        func snap(_ edge: CGFloat, to lines: [CGFloat], tolerance: CGFloat, staysOut: (CGFloat) -> Bool) -> CGFloat {
            lines.filter { abs($0 - edge) <= tolerance && staysOut($0) }.min { abs($0 - edge) < abs($1 - edge) } ?? edge
        }
        let left = snap(boxed.minX, to: xs, tolerance: tolerance.width) { $0 <= subject.minX }
        let right = snap(boxed.maxX, to: xs, tolerance: tolerance.width) { $0 >= subject.maxX && $0 <= full.maxX }
        let top = snap(boxed.minY, to: ys, tolerance: tolerance.height) { $0 <= subject.minY }
        let bottom = snap(boxed.maxY, to: ys, tolerance: tolerance.height) { $0 >= subject.maxY && $0 <= full.maxY }
        let snapped = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard snapped.width >= 2, snapped.height >= 2 else { return boxed }
        return snapped
    }

    /// The gray levels of `image` as one byte per pixel, row 0 at the top edge.
    private static func levels(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var bottomUp = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &bottomUp, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The bitmap fills bottom-up; turn the rows around so callers get the top-left grid.
        var levels: [UInt8] = []
        levels.reserveCapacity(width * height)
        for y in stride(from: height - 1, through: 0, by: -1) {
            levels.append(contentsOf: bottomUp[(y * width)..<(y * width + width)])
        }
        return levels
    }
}
