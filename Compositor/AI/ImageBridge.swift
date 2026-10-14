import AppKit
import Foundation

/// Bridges between CGImage and gateway API formats (base64, multipart).
enum ImageBridge {
    
    /// Converts a CGImage to PNG data.
    static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
    
    /// Converts a CGImage to JPEG data with quality.
    static func jpegData(from image: CGImage, quality: CGFloat = 0.9) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
    
    /// Converts PNG/JPEG data to CGImage.
    static func cgImage(from data: Data) -> CGImage? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }
    
    /// Converts a CGImage to base64 string (PNG format).
    static func base64(from image: CGImage) -> String? {
        guard let data = pngData(from: image) else { return nil }
        return data.base64EncodedString()
    }
    
    /// Converts base64 string to CGImage.
    static func cgImage(fromBase64 base64: String) -> CGImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return cgImage(from: data)
    }
    
    /// Creates a multipart part for an image (PNG format).
    static func multipartPart(for image: CGImage, name: String, filename: String = "image.png") -> MultipartPart? {
        guard let data = pngData(from: image) else { return nil }
        return .data(name, data, filename: filename, mimeType: "image/png")
    }
    
    /// Downloads an image from a URL and returns CGImage.
    static func downloadImage(from url: URL) async throws -> CGImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = cgImage(from: data) else {
            throw ImageBridgeError.invalidImageData
        }
        return image
    }
    
    /// Loads an image from a file URL.
    static func loadImage(from fileURL: URL) throws -> CGImage {
        let data = try Data(contentsOf: fileURL)
        guard let image = cgImage(from: data) else {
            throw ImageBridgeError.invalidImageData
        }
        return image
    }
}

enum ImageBridgeError: Error, LocalizedError {
    case invalidImageData
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        case .conversionFailed:
            return "Image conversion failed"
        }
    }
}
