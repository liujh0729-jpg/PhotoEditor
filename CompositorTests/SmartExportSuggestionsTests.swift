import Foundation
import Testing
@testable import Compositor

/// The export suggestions without the sheet: the purpose table, the contain-not-cover math, and whether
/// every string the menu shows is translated in all seven catalogs.
struct SmartExportSuggestionsTests {
    @Test func everyUseCaseHasABox() {
        for useCase in SmartExportSuggestions.UseCase.allCases {
            #expect(useCase.target.width > 0 && useCase.target.height > 0, "\(useCase.rawValue) needs a pixel box")
            #expect(useCase.quality >= 0 && useCase.quality <= 1, "\(useCase.rawValue)'s quality is a fraction")
        }
    }

    @Test func platformPicks() {
        let tall = SmartExportSuggestions.suggest(.instagramPost, width: 4000, height: 3000)
        #expect(tall.width == 1080 && tall.height == 810, "a landscape canvas fills Instagram's square from the top")
        #expect(tall.format == .png, "Instagram takes the lossless file and recompresses it anyway")

        let wide = SmartExportSuggestions.suggest(.xPost, width: 3000, height: 4000)
        #expect(wide.width == 675 && wide.height == 900, "a portrait canvas fits X's banner by its height")
        #expect(wide.format == .jpeg && wide.quality == 0.8)

        let note = SmartExportSuggestions.suggest(.xiaohongshuNote, width: 4000, height: 3000)
        #expect(note.width == 1242 && note.height == 932, "Xiaohongshu's portrait box caps a landscape canvas at its width")

        let print = SmartExportSuggestions.suggest(.print300, width: 4000, height: 3000)
        #expect(print.width == 2400 && print.height == 1800, "8×10 in at 300 DPI, capped by the width")
        #expect(print.format == .tiff && print.cmyk, "the printer gets ink, not JPEG")

        let web = SmartExportSuggestions.suggest(.web, width: 900, height: 500)
        #expect(web.width == 900 && web.height == 500, "a canvas under the box keeps the pixels it has")
        #expect(web.format == .jpeg && web.quality == 0.7, "the web ships light")
        #expect(!web.cmyk)
    }

    @Test func degenerateCanvasStillSuggests() {
        // A size read off a layer can be zero while it's being made; the suggestion must not divide by it.
        let odd = SmartExportSuggestions.suggest(.web, width: 0, height: 0)
        #expect(odd.width >= 1 && odd.height >= 1)
    }

    @Test func menuStringsAreTranslated() throws {
        let keys = SmartExportSuggestions.UseCase.allCases.map(\.rawValue) + [
            "Suggest Settings",
            "Fill the size, format and quality the purpose's platform likes best, keeping the canvas's proportions",
        ]
        for localization in ["zh-Hans", "ja", "fr", "es", "ru", "vi", "ar"] {
            let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                     inDirectory: "\(localization).lproj"),
                                    "\(localization) catalog ships with the app")
            // The build copies catalogs as UTF-16; the repo keeps them UTF-8. Read whichever this is.
            let text: String
            if let utf16 = try? String(contentsOfFile: path, encoding: .utf16), utf16.contains("=") {
                text = utf16
            } else {
                text = try String(contentsOfFile: path, encoding: .utf8)
            }
            for key in keys {
                #expect(text.contains("\"\(key)\" ="), "\(key) missing from \(localization)")
            }
        }
    }
}
