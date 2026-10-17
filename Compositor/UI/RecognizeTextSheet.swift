import SwiftUI

/// On-device OCR sheet: Vision reads the words the canvas holds and lists them, top to bottom. Copy them out,
/// or lay them back on the canvas as a live-text layer. Nothing is uploaded, so it keeps working in Privacy Mode.
struct RecognizeTextSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [RecognizedText] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recognize Text")
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
                    Text("Reading the text…")
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Vision reads the words on this Mac — it works offline and in Privacy Mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 220, alignment: .leading)
                
                Spacer()
                
                Button("Copy All") {
                    copyAll()
                }
                .disabled(lines.isEmpty)
                
                Button("Insert as Text Layer") {
                    insert()
                }
                .disabled(lines.isEmpty)
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 480)
        .background(Color(white: 0.14))
        .task { recognize() }
    }
    
    private func recognize() {
        isProcessing = true
        errorMessage = nil
        // The same sample the selection tools read: what the canvas actually shows.
        guard let document = session.document,
              let sample = session.selectionSample(document, sampleAllLayers: true) else {
            isProcessing = false
            errorMessage = "There's nothing on the canvas to read."
            return
        }
        Task {
            do {
                lines = try await TextRecognition.recognize(in: sample)
                isProcessing = false
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
        dismiss()
    }
    
    private func insert() {
        guard session.insertRecognizedText(lines.map(\.text).joined(separator: "\n")) else {
            errorMessage = "Can't add a text layer here. Try again once the canvas is editable."
            return
        }
        dismiss()
    }
}
