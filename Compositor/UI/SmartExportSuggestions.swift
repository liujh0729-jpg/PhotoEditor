import Foundation

/// Export As' smart suggestions: what each everyday purpose wants the export to be, worked out from the
/// canvas's own proportions. Rules only — no model, no network — so a suggestion is the same on every Mac
/// and each one is verifiable on its own.
nonisolated enum SmartExportSuggestions {
    /// A purpose the panel offers, with the box its platform likes best, in pixels.
    enum UseCase: String, CaseIterable, Codable {
        case instagramPost = "Instagram Post"
        case xPost = "X Post"
        case xiaohongshuNote = "Xiaohongshu Note"
        case print300 = "Print (300 DPI)"
        case web = "Web"

        /// The pixel box the purpose's platform fits inside; the canvas keeps its own proportions inside it.
        var target: CGSize {
            switch self {
            case .instagramPost: return CGSize(width: 1080, height: 1080)
            case .xPost: return CGSize(width: 1600, height: 900)
            case .xiaohongshuNote: return CGSize(width: 1242, height: 1660)
            case .print300: return CGSize(width: 2400, height: 3000)
            case .web: return CGSize(width: 1600, height: 1600)
            }
        }

        /// The format the purpose ships in: lossless for the platforms that recompress anyway, ink for the printer.
        var format: ExportFormat {
            switch self {
            case .instagramPost: return .png
            case .xPost, .xiaohongshuNote: return .jpeg
            case .print300: return .tiff
            case .web: return .jpeg
            }
        }

        /// JPEG's quality for the purpose; social feeds and the web are shown at a fraction of this size anyway.
        var quality: Double {
            switch self {
            case .xPost, .xiaohongshuNote: return 0.8
            case .web: return 0.7
            default: return 1
            }
        }

        /// Only the printer wants a printer's inks.
        var cmyk: Bool { self == .print300 }
    }

    /// A suggestion applied to the export sheet: the size to fill the purpose's box with the canvas's
    /// proportions, and the format, quality and color space that go with it.
    struct Suggestion: Equatable {
        let useCase: UseCase
        let width: Int
        let height: Int
        let format: ExportFormat
        let quality: Double
        let cmyk: Bool
    }

    /// The suggestion for `useCase` given a `width` × `height` canvas. Contain, never cover: no crop, and a
    /// canvas smaller than the box keeps the pixels it has rather than being inflated.
    static func suggest(_ useCase: UseCase, width: Int, height: Int) -> Suggestion {
        let scale: Double
        if width > 0, height > 0 {
            scale = min(1, min(useCase.target.width / Double(width), useCase.target.height / Double(height)))
        } else {
            scale = 1
        }
        return Suggestion(useCase: useCase,
                          width: max(1, Int((Double(width) * scale).rounded())),
                          height: max(1, Int((Double(height) * scale).rounded())),
                          format: useCase.format, quality: useCase.quality, cmyk: useCase.cmyk)
    }
}
