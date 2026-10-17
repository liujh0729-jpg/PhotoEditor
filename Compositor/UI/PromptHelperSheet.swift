import AppKit
import SwiftUI

/// The Prompt Assistant: it reads the layer's name and, when asked, the picture on the canvas, and asks the chat
/// model to draft an editable prompt. Nothing is applied — the words land in a field the artist tweaks and copies.
struct PromptHelperSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var suggestion: String = ""
    @State private var usePicture = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prompt Assistant…")
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
                Section("What do you want to do?") {
                    TextEditor(text: $note)
                        .frame(height: 70)
                        .font(.body)
                }
                Toggle("Use the picture on the canvas", isOn: $usePicture)
                    .disabled(isWorking)

                Button("Suggest a prompt") { suggest() }
                    .disabled(isWorking)

                Section("Prompt") {
                    if isWorking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").foregroundColor(.secondary)
                        }
                    } else if suggestion.isEmpty {
                        Text(errorMessage ?? "No prompt yet")
                            .foregroundColor(.secondary)
                    } else {
                        TextEditor(text: $suggestion)
                            .frame(height: 110)
                            .font(.body)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("The layer's name and the picture on the canvas go to the chat model the slot names.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 260, alignment: .leading)
                Spacer()
                Button("Copy") { copy() }
                    .disabled(suggestion.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 460)
        .background(Color(white: 0.14))
    }

    private func suggest() {
        isWorking = true
        errorMessage = nil
        let layerName = session.activeLayer?.name
        let context = PromptHelper.context(layerName: layerName, note: note)
        let picture: CGImage? = usePicture
            ? session.document.flatMap { session.selectionSample($0, sampleAllLayers: true) }
            : nil
        Task {
            do {
                suggestion = try await PromptHelper.suggest(context: context, selection: picture)
                isWorking = false
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy() {
        guard !suggestion.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)
    }
}
