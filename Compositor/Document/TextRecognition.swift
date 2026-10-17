import AppKit
import Vision

/// A run of text Vision read off a picture, with its box in the image's own pixel grid, top-left origin.
nonisolated struct RecognizedText: Sendable {
    let text: String
    let box: CGRect
}

/// On-device OCR: Vision reads the words a picture holds. Nothing leaves the Mac, so it works in Privacy Mode.
nonisolated enum TextRecognition {
    enum Failure: LocalizedError {
        case noText
        var errorDescription: String? { "No readable text was found in this picture." }
    }

    /// The words in `image`, top to bottom. Vision reads in the system's languages; Chinese is always one of them.
    static func recognize(in image: CGImage) async throws -> [RecognizedText] {
        // The accurate pass is real work on a big canvas; the global executor keeps the editor from waiting on it.
        try await Task.detached(priority: .userInitiated) { try read(image) }.value
    }

    private static func read(_ image: CGImage) throws -> [RecognizedText] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // A fresh request reads in the system's languages; Chinese is what the editor promises on top of them.
        var languages = request.recognitionLanguages ?? ["en-US"]
        if !languages.contains(where: { $0.hasPrefix("zh") }) { languages.insert("zh-Hans", at: 0) }
        request.recognitionLanguages = languages
        try handler.perform([request])
        guard let observations = request.results, !observations.isEmpty else { throw Failure.noText }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision's box is normalized from the bottom up; the picture's own grid starts at the top left.
            let box = observation.boundingBox
            return RecognizedText(text: candidate.string,
                                  box: CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                                              width: box.width * width, height: box.height * height))
        }
        .sorted { $0.box.minY < $1.box.minY }
    }
}
