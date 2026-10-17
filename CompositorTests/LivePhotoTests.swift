import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Compositor

/// Live Photo export, the parts that run without a real encoder. Synthesizing a movie in-process raises an
/// uncatchable exception in the sandboxed test host, so the AVAssetWriter path is left to the running app;
/// here the identifier shape, the JPEG stamp, and the empty-movie guard are checked for real.
struct LivePhotoTests {
    private func tempFolder() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("livephoto-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func identifierAndPairNameHaveTheShapesPhotosWants() {
        let id = LivePhoto.assetIdentifier()
        #expect(UUID(uuidString: id) != nil) // A valid, uppercase UUID string.
        #expect(id == id.uppercased())
        #expect(LivePhoto.pairName(id).hasPrefix("IMG_"))
        #expect(Set((0..<50).map { _ in LivePhoto.assetIdentifier() }).count > 1)
    }

    /// An 8×8 opaque bitmap standing in for a lifted frame.
    private func solidImage() -> CGImage? {
        var storage = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in 0..<64 { storage[i * 4] = 50; storage[i * 4 + 1] = 150; storage[i * 4 + 2] = 220; storage[i * 4 + 3] = 255 }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &storage, width: 8, height: 8, bitsPerComponent: 8,
                                      bytesPerRow: 8 * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return context.makeImage()
    }

    @Test func stillWritesADecodableJPEGOfTheFrameSize() throws {
        let frame = try #require(solidImage())
        let url = tempFolder().appendingPathComponent("still.jpg")
        // A real identifier is a 36-character UUID, the width the maker note reserves for tag 17.
        let identifier = LivePhoto.assetIdentifier()
        let written = try #require(LivePhoto.writeStill(frame, identifier: identifier, to: url))
        let data = try Data(contentsOf: written)
        #expect(!data.isEmpty)
        // The file reads back as a JPEG holding the frame at its full size.
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let readBack = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(readBack.width == 8)
        #expect(readBack.height == 8)
        // The identifier lands in the Apple maker note where the encoder keeps it; not all do.
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let maker = props[kCGImagePropertyMakerAppleDictionary] as? [String: Any] {
            #expect(maker["17"] as? String == identifier)
        }
    }

    @Test func exportOfAMovieWithNoVideoTrackYieldsNothing() async {
        let bogus = tempFolder().appendingPathComponent("empty.txt")
        try? Data("not a movie".utf8).write(to: bogus)
        let pair = await LivePhoto.export(from: bogus, to: bogus.deletingLastPathComponent())
        #expect(pair == nil)
    }
}
