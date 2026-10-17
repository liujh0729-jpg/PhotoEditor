import CoreGraphics
import Foundation

/// The prompt helper: it reads what the artist has on the canvas — the layer's name and, when there's a
/// selection, its thumbnail — and asks the chat model to turn that into a prompt they can edit. The answer is
/// a suggestion, dropped into a text field, never applied on its own. The context and the wire messages are
/// built as pure functions so the request shape is checkable without a network.
enum PromptHelper {
    /// The standing instruction. English always: it's a prompt, not UI text.
    static let instruction = """
    You write prompts for an image model. Using what the artist has on the canvas, draft one vivid prompt \
    of one to three sentences that they can edit. Reply with only the prompt, no quotes or preamble.
    """

    /// A short line describing the canvas the model is being asked to prompt for.
    static func context(layerName: String?, note: String?) -> String {
        var lines: [String] = []
        if let name = layerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            lines.append("Layer: \(name).")
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            lines.append("The artist wants to: \(note).")
        }
        if lines.isEmpty { lines.append("No description; use the picture itself.") }
        return lines.joined(separator: " ")
    }

    /// The messages a request carries: the instruction and context in a user turn, the thumbnail beside it
    /// when one was picked up.
    static func messages(context: String, selectionBase64: String?) -> [ChatCompletionRequest.ChatMessage] {
        var parts: [ChatCompletionRequest.ChatMessage.Content.Part] = [.text("\(instruction)\n\n\(context)")]
        if let base64 = selectionBase64 {
            parts.append(.imageURL("data:image/png;base64,\(base64)"))
        }
        return [.init(role: "user", parts: parts)]
    }

    /// The model's answer made fit for the field: trimmed, with any wrapping quotes or code fences dropped. The
    /// model is told not to add them, but it often does anyway.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("```") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for pair in [("\"", "\""), ("“", "”"), ("'", "'")] where text.count >= 2 && text.hasPrefix(pair.0) && text.hasSuffix(pair.1) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return text
    }

    /// Asks the chat slot's model for a prompt. Empty or whitespace-only answers are a failure, the way the
    /// description sheet reads the model.
    static func suggest(context: String, selection: CGImage?) async throws -> String {
        let base64 = selection.flatMap { ImageBridge.base64(from: $0) }
        let request = ChatCompletionRequest(
            model: GatewayConfigurationStore.shared.model(for: .chat) ?? "gpt-4o",
            messages: messages(context: context, selectionBase64: base64),
            temperature: 0.7
        )
        let response: ChatCompletionResponse = try await GatewayClient.shared.request(
            endpoint: .chat, body: request, as: ChatCompletionResponse.self)
        let raw = response.choices.first?.message.content ?? ""
        let text = clean(raw)
        guard !text.isEmpty else { throw GatewayClientError.invalidResponse }
        return text
    }
}
