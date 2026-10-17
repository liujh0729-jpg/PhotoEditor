import SwiftUI

/// Sheet for semantic selection: Vision cuts the subject mask on this Mac, and the prompt names the edit it becomes.
struct SemanticSelectionSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt: String = ""
    @State private var model: String = ""
    @State private var threshold: Double = 0.5
    
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var maskPreview: CGImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Semantic Selection")
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
            
            // Content
            HStack(spacing: 0) {
                // Left: Parameters
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        Section("Prompt") {
                            TextEditor(text: $prompt)
                                .frame(height: 100)
                                .font(.body)
                            
                            Text("Describe what you want to select, e.g., 'the cat', 'the sky', 'the person on the left'")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("The mask is made on this Mac by Vision, so it works offline. Your prompt names the edit.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Section("Settings") {
                            HStack {
                                Text("Model")
                                Spacer()
                                TextField("Default", text: $model)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Threshold")
                                Spacer()
                                Slider(value: $threshold, in: 0...1)
                                    .frame(width: 150)
                                Text(String(format: "%.2f", threshold))
                                    .frame(width: 50)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Preview
                VStack(spacing: 16) {
                    if let mask = maskPreview {
                        Image(nsImage: NSImage(cgImage: mask, size: .zero))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .padding()
                        
                        HStack {
                            Button("Apply as Mask") {
                                applyAsMask()
                            }
                            Button("Apply as Selection") {
                                applyAsSelection()
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.dashed.badge.record")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No mask generated yet")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Divider()
            
            // Footer
            HStack {
                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating mask…")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Generate") {
                    generate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func generate() {
        isProcessing = true
        errorMessage = nil
        maskPreview = nil
        // The mask is read off what the canvas shows, the same sample the Object Selection tool works from.
        guard let document = session.document,
              let sample = session.selectionSample(document, sampleAllLayers: true) else {
            isProcessing = false
            errorMessage = "There's nothing on the canvas to read."
            return
        }
        let cutoff = threshold
        Task {
            do {
                let mask = try await Task.detached(priority: .userInitiated) {
                    try SemanticSelection.subjectMask(in: sample, threshold: cutoff)
                }.value
                isProcessing = false
                maskPreview = mask
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    /// The prompt names the edit in History; the subject itself is Vision's call.
    private var subjectName: String? {
        let name = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
    
    private func applyAsMask() {
        guard let mask = maskPreview else { return }
        guard session.applySemanticMask(mask, name: subjectName) else {
            errorMessage = "Can't add a mask here — select one layer first."
            return
        }
        dismiss()
    }
    
    private func applyAsSelection() {
        guard let mask = maskPreview else { return }
        guard session.applySemanticSelection(mask, name: subjectName) else {
            errorMessage = "The mask didn't enclose anything to select."
            return
        }
        dismiss()
    }
}
