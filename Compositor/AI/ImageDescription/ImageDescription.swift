import CoreGraphics
import Foundation

/// What the chat model sees of the canvas: the picture as an OpenAI-compatible image part next to the
/// instruction, the answer a couple of sentences the sheet can copy or file into the project.
enum ImageDescription {
    /// The question the picture travels with. English always: it's a prompt, not UI text.
    static let instruction = "Describe this image in one or two sentences, the way a photo archive would file it."

    /// The messages a description request carries: instruction and picture in one user turn.
    static func messages(base64: String) -> [ChatCompletionRequest.ChatMessage] {
        [.init(role: "user", parts: [.text(instruction), .imageURL("data:image/png;base64,\(base64)")])]
    }

    /// Asks the chat slot's model about the picture. The model's words, trimmed; empty answers are a failure.
    static func describe(_ image: CGImage) async throws -> String {
        guard let base64 = ImageBridge.base64(from: image) else { throw GatewayClientError.invalidResponse }
        let request = ChatCompletionRequest(
            model: GatewayConfigurationStore.shared.model(for: .chat) ?? "gpt-4o",
            messages: messages(base64: base64),
            temperature: 0.3
        )
        let response: ChatCompletionResponse = try await GatewayClient.shared.request(
            endpoint: .chat,
            body: request,
            as: ChatCompletionResponse.self
        )
        let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw GatewayClientError.invalidResponse }
        return text
    }
}
