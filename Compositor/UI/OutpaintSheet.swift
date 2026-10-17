import SwiftUI

/// Outpainting sheet: pick how far to grow the canvas and what to paint there, then run the request. The canvas
/// enlarges with the picture centered, only the fresh border is sent as the mask, and the answer lands as a new
/// layer — the same pipeline the Retouch panel uses, so it folds into history like any other change.
struct OutpaintSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var marginPercent: Double = 15
    @State private var prompt: String = ""
    @State private var model: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var margin: Int {
        guard let document = session.document else { return 0 }
        return max(1, Int((Double(min(document.width, document.height)) * marginPercent / 100).rounded()))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outpaint")
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

            Form {
                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(height: 80)
                        .font(.body)
                }

                Section("Settings") {
                    HStack {
                        Text("Margin")
                        Spacer()
                        Slider(value: $marginPercent, in: 5...50)
                            .frame(width: 180)
                        Text("\(Int(marginPercent))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("Model")
                        Spacer()
                        TextField("Slot default", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }

                Section {
                    Text("Grow the canvas and let the model paint only the new edges. The picture itself stays as it is.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let document = session.document {
                        Text("New size: \(document.width + 2 * margin) × \(document.height + 2 * margin)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(CatalogStore.shared.estimate(for: .imageEdits, prompt: prompt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Extend") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.isEmpty || isProcessing || session.document == nil)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .background(Color(white: 0.14))
    }

    private func run() {
        guard session.document != nil, !prompt.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        let resolvedModel = model.isEmpty
            ? (GatewayConfigurationStore.shared.model(for: .imageEdits) ?? "gpt-image-1")
            : model
        let margin = self.margin
        let prompt = self.prompt
        Task {
            let ok = await session.outpaint(margin: margin, prompt: prompt, model: resolvedModel) { padded, mask in
                let parts = Outpaint.multipartParts(paddedImage: padded, mask: mask, prompt: prompt, model: resolvedModel)
                let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: .imageEdits, parts: parts, as: ImageResponse.self)
                return try await RestoreSheet.firstImage(of: response)
            }
            isProcessing = false
            if ok {
                dismiss()
            } else {
                errorMessage = "Couldn't extend the image. Check the prompt and try again."
            }
        }
    }
}
