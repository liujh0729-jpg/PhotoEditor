import Foundation
import Testing
@testable import Compositor

/// The prompt helper without a network: how the canvas is turned into a context line, what the request's
/// messages carry (the thumbnail rides along only when one was picked up), and how the model's answer is
/// tidied for the field. Plus the catalog coverage for the strings the sheet shows.
struct PromptHelperTests {
    // MARK: Context

    @Test func contextFoldsLayerNameAndNote() {
        let text = PromptHelper.context(layerName: "Sky", note: "add storm clouds")
        #expect(text.contains("Sky"))
        #expect(text.contains("add storm clouds"))
    }

    @Test func contextFallsBackWhenThereIsNothingToSay() {
        let text = PromptHelper.context(layerName: "   ", note: nil)
        #expect(text.contains("No description"))
    }

    // MARK: Messages

    private func parts(of message: ChatCompletionRequest.ChatMessage) -> [ChatCompletionRequest.ChatMessage.Content.Part] {
        guard case .parts(let parts) = message.content else { return [] }
        return parts
    }

    @Test func messagesCarryInstructionAndContextWithoutAPicture() {
        let messages = PromptHelper.messages(context: "Layer: Sky.", selectionBase64: nil)
        #expect(messages.count == 1)
        #expect(messages[0].role == "user")
        let parts = parts(of: messages[0])
        #expect(parts.count == 1, "no thumbnail, one text part")
        guard case .text(let text) = parts[0] else { Issue.record("expected a text part"); return }
        #expect(text.contains(PromptHelper.instruction))
        #expect(text.contains("Layer: Sky."))
    }

    @Test func messagesAddAnImagePartWhenAThumbnailIsGiven() {
        let messages = PromptHelper.messages(context: "Layer: Sky.", selectionBase64: "QUJD")
        let parts = parts(of: messages[0])
        #expect(parts.count == 2, "the picture travels beside the words")
        guard case .imageURL(let url) = parts[1] else { Issue.record("expected an image part"); return }
        #expect(url == "data:image/png;base64,QUJD")
    }

    // MARK: Cleaning the answer

    @Test func cleanTrimsAndDropsWrappingQuotes() {
        #expect(PromptHelper.clean("  \"A storm rolls in.\"  ") == "A storm rolls in.")
        #expect(PromptHelper.clean("“Curly quotes too.”") == "Curly quotes too.")
    }

    @Test func cleanStripsCodeFences() {
        #expect(PromptHelper.clean("```\na prompt\n```") == "a prompt")
    }

    @Test func cleanLeavesAPlainAnswerAlone() {
        #expect(PromptHelper.clean("Misty pines at dawn.") == "Misty pines at dawn.")
    }

    // MARK: Catalogs

    private var sheetKeys: [String] {
        [
            "Prompt Assistant…",
            "What do you want to do?",
            "Use the picture on the canvas",
            "Suggest a prompt",
            "Thinking…",
            "No prompt yet",
            "The layer's name and the picture on the canvas go to the chat model the slot names.",
        ]
    }

    private func catalogKeys(forLocalization localization: String) throws -> Set<String> {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                 inDirectory: "\(localization).lproj"))
        let text: String
        if let utf16 = try? String(contentsOfFile: path, encoding: .utf16), utf16.contains("=") {
            text = utf16
        } else {
            text = try String(contentsOfFile: path, encoding: .utf8)
        }
        var keys = Set<String>()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            keys.insert(String(key.dropFirst().dropLast()))
        }
        return keys
    }

    @Test func sheetStringsAreTranslated() throws {
        for localization in ["zh-Hans", "ja", "fr", "es", "ru", "vi", "ar"] {
            let keys = try catalogKeys(forLocalization: localization)
            for key in sheetKeys {
                #expect(keys.contains(key), "\(key) missing from \(localization)")
            }
        }
    }
}
