import SwiftUI
import UniformTypeIdentifiers

/// Sheet for style transfer (reference image → color tone).
struct StyleTransferSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    
    let sourceImage: CGImage?
    
    @State private var referenceImage: CGImage?
    @State private var model: String = ""
    @State private var strength: Double = 0.7
    
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var resultImage: CGImage?
    
    init(session: EditorSession, sourceImage: CGImage? = nil) {
        self.session = session
        self.sourceImage = sourceImage
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Style Transfer")
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
                        Section("Reference Image") {
                            Button("Choose Reference…") {
                                chooseReference()
                            }
                            
                            if let ref = referenceImage {
                                Image(nsImage: NSImage(cgImage: ref, size: .zero))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 150)
                                    .cornerRadius(4)
                            }
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
                                Text("Strength")
                                Spacer()
                                Slider(value: $strength, in: 0...1)
                                    .frame(width: 150)
                                Text(String(format: "%.0f%%", strength * 100))
                                    .frame(width: 50)
                            }
                        }
                        
                        if let source = sourceImage {
                            Section("Source") {
                                Image(nsImage: NSImage(cgImage: source, size: .zero))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 100)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Preview
                VStack(spacing: 16) {
                    if let result = resultImage {
                        Image(nsImage: NSImage(cgImage: result, size: .zero))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .padding()
                        
                        HStack {
                            Button("Apply to Layer") {
                                applyToLayer()
                            }
                            Button("Add as New Layer") {
                                addAsNewLayer()
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No result yet")
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
                        Text("Transferring style…")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Transfer") {
                    transfer()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(referenceImage == nil || sourceImage == nil || isProcessing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func chooseReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            referenceImage = try? ImageBridge.loadImage(from: url)
        }
    }
    
    private func transfer() {
        guard let source = sourceImage, let reference = referenceImage else { return }
        
        isProcessing = true
        errorMessage = nil
        resultImage = nil
        
        Task {
            do {
                var parts: [MultipartPart] = []
                
                guard let sourcePart = ImageBridge.multipartPart(for: source, name: "image"),
                      let referencePart = ImageBridge.multipartPart(for: reference, name: "reference") else {
                    isProcessing = false
                    errorMessage = "Could not encode the source or reference image."
                    return
                }
                parts.append(sourcePart)
                parts.append(referencePart)
                parts.append(.text("prompt", "Match the color tone and style of the reference image."))
                parts.append(.text("strength", String(format: "%.2f", strength)))
                parts.append(.text("response_format", "b64_json"))
                if !model.isEmpty {
                    parts.append(.text("model", model))
                }
                
                let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: .imageEdits,
                    parts: parts,
                    as: ImageResponse.self
                )
                
                if let imageData = response.data.first {
                    if let b64 = imageData.b64_json, let image = ImageBridge.cgImage(fromBase64: b64) {
                        resultImage = image
                    } else if let urlStr = imageData.url, let url = URL(string: urlStr) {
                        resultImage = try await ImageBridge.downloadImage(from: url)
                    }
                }
                
                if resultImage == nil {
                    errorMessage = "The style transfer didn't return an image."
                }
                isProcessing = false
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func applyToLayer() {
        guard let result = resultImage else { return }
        session.replaceActiveLayer(with: result)
        dismiss()
    }
    
    private func addAsNewLayer() {
        guard let result = resultImage else { return }
        session.placeGeneratedImage(result, named: "Style Transfer")
        dismiss()
    }
}
