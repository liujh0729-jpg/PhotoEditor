import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Live Photo export: the video the gateway made becomes the two assets a Live Photo is — a still (the
/// first frame, as a JPEG) and the short movie — stamped with the same content identifier so Photos pairs
/// them. The still and the movie are written beside each other into a folder the person picks.
///
/// Writing straight into the Photos library would need the photo-library entitlement and a signed build;
/// it is left as the last manual step (drop the folder onto Photos, or call PHPhotoLibrary's paired add).
enum LivePhoto {
    /// The identifier both halves carry. Uppercase UUID string, the shape Photos expects.
    static func assetIdentifier() -> String { UUID().uuidString }

    /// The base name a pair shares: without a matching stem Photos won't look for the partner file.
    static func pairName(_ identifier: String) -> String { "IMG_" + identifier.prefix(8) }

    /// The first frame of the movie, as it will be filed. nil if the file has no readable video track.
    static func stillFrame(of videoURL: URL) async -> CGImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true // Stand the frame up the way the movie plays it.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard asset.tracks(withMediaType: .video).first != nil else { return nil }
        let image = try? await generator.image(at: .zero).image
        return image
    }

    /// Writes the JPEG still, tagged with the pair's content identifier in the QuickTime-style metadata
    /// ImageIO carries. Returns the file URL, or nil if the frame couldn't be encoded.
    static func writeStill(_ frame: CGImage, identifier: String, to url: URL) -> URL? {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        // The asset identifier lives in the Apple maker note; Photos reads it there to find the movie.
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72,
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
        ]
        CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    /// Copies the movie next to the still, stamping it with the same content identifier through QuickTime
    /// metadata, so the folder holds a pair Photos can reunite.
    static func writePairedMovie(from videoURL: URL, identifier: String, to url: URL) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let identifierItem = AVMutableMetadataItem()
        identifierItem.keySpace = .quickTimeMetadata
        identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        identifierItem.value = identifier as NSString
        identifierItem.dataType = "com.apple.metadata.datatype.UTF-8"
        // A compatible copy keeps the original codec; re-encoding a short clip only risks a stall.
        let preset: String = asset.isPlayable ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            return (try? FileManager.default.copyItem(at: videoURL, to: url)) != nil ? url : nil
        }
        session.outputURL = url
        session.outputFileType = .mov
        session.metadata = [identifierItem]
        await session.export()
        if session.status == .completed, FileManager.default.fileExists(atPath: url.path) { return url }
        // If the export couldn't restamp the file, fall back to a plain copy that at least keeps the pair's name.
        try? FileManager.default.removeItem(at: url)
        return (try? FileManager.default.copyItem(at: videoURL, to: url)) != nil ? url : nil
    }

    /// Builds the whole pair from a movie file: pull the first frame, write the still and the restamped
    /// movie under a shared name in `folder`. Returns both URLs, or nil when the movie had no frame to lift.
    static func export(from videoURL: URL, to folder: URL) async -> (still: URL, movie: URL)? {
        guard let frame = await stillFrame(of: videoURL) else { return nil }
        let identifier = assetIdentifier()
        let base = pairName(identifier)
        let stillURL = folder.appendingPathComponent("\(base).jpg")
        let movieURL = folder.appendingPathComponent("\(base).mov")
        guard writeStill(frame, identifier: identifier, to: stillURL) != nil,
              await writePairedMovie(from: videoURL, identifier: identifier, to: movieURL) != nil
        else { return nil }
        return (stillURL, movieURL)
    }
}

private extension AVAsset {
    /// Whether the asset has at least one decodable video track — the cheap stand-in export-availability check.
    var isPlayable: Bool { !tracks(withMediaType: .video).isEmpty }
}
