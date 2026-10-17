import SwiftUI

/// The Image Description sheet: the chat model looks at the canvas and says what it sees. Copy the sentence
/// out, or file it on the project — it rides the manifest from the next save onward, so the description stays
/// with the .comp package.
struct ImageDescriptionSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var description: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Image Description…")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Body
            if isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Describing…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let description {
                ScrollView {
                    Text(description)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text(errorMessage ?? "There's nothing on the canvas to describe.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("The canvas picture goes to the chat model the slot names.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 220, alignment: .leading)

                Spacer()

                Button("Copy") {
                    copy()
                }
                .disabled(description == nil)

                Button("Save to Project") {
                    save()
                }
                .disabled(description == nil)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .background(Color(white: 0.14))
        .task { describe() }
    }

    private func describe() {
        isProcessing = true
        errorMessage = nil
        // The same sample the reading tools use: what the canvas actually shows.
        guard let document = session.document,
              let sample = session.selectionSample(document, sampleAllLayers: true) else {
            isProcessing = false
            errorMessage = "There's nothing on the canvas to describe."
            return
        }
        Task {
            do {
                description = try await ImageDescription.describe(sample)
                isProcessing = false
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy() {
        guard let description else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(description, forType: .string)
        dismiss()
    }

    private func save() {
        guard let description else { return }
        session.aiDescription = description
        dismiss()
    }
}
