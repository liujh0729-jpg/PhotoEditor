import SwiftUI

/// Sheet for semantic selection (text-to-mask).
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
                .disabled(prompt.isEmpty || isProcessing)
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
        
        Task {
            do {
                // TODO: Implement actual semantic selection API call
                // This would typically use a SAM-like model or segmentation API
                // For now, this is a placeholder
                
                try await Task.sleep(nanoseconds: 2_000_000_000)  // Simulate processing
                
                // Placeholder: create a dummy mask
                // In reality, this would come from the gateway
                
                isProcessing = false
                errorMessage = "Semantic selection not yet implemented. Requires SAM or similar model."
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func applyAsMask() {
        guard let mask = maskPreview else { return }
        guard session.applySemanticMask(mask) else {
            errorMessage = "Can't add a mask here — select one layer first."
            return
        }
        dismiss()
    }
    
    private func applyAsSelection() {
        guard let mask = maskPreview else { return }
        guard session.applySemanticSelection(mask) else {
            errorMessage = "The mask didn't enclose anything to select."
            return
        }
        dismiss()
    }
}
