import SwiftUI

/// Text replacement sheet: Vision reads the words the active layer holds, the artist picks one and types what should
/// stand in its place. The gateway lifts the old words out of the picture and the new ones land back over the same
/// spot as a live-text layer. The reading is local, but the erase asks the gateway, so this is gated off in Privacy Mode.
struct TextReplacementSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [RecognizedText] = []
    @State private var selected: Int?
    @State private var replacement: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Replace Text")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark").font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if isProcessing {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text(errorMessage ?? "No readable text was found in this picture.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selected) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text).tag(index)
                    }
                }
                .environment(\.defaultMinListRowHeight, 24)
            }

            Divider()

            HStack {
                TextField("New text", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Replace") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .background(Color(white: 0.14))
        .task { recognize() }
    }

    private func recognize() {
        guard let image = session.activeLayer?.asset?.image else {
            errorMessage = "Select a layer with text on it first."
            return
        }
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                lines = try await TextRecognition.recognize(in: image)
                if lines.isEmpty { errorMessage = "No readable text was found in this picture." }
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func run() {
        guard let index = selected, lines.indices.contains(index) else { return }
        let line = lines[index]
        let newText = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        let model = GatewayConfigurationStore.shared.model(for: .imageEdits) ?? "gpt-image-1"
        Task {
            let ok = await session.replaceText(in: line.box, newText: newText, model: model) { image, mask in
                let parts = TextReplacement.multipartParts(image: image, mask: mask, model: model)
                let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: .imageEdits, parts: parts, as: ImageResponse.self)
                return try await RestoreSheet.firstImage(of: response)
            }
            isProcessing = false
            if ok {
                dismiss()
            } else {
                errorMessage = "Couldn't replace the text. Try again."
            }
        }
    }
}
