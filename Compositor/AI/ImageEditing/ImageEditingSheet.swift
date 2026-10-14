import SwiftUI
import UniformTypeIdentifiers

/// Sheet for editing images (image-to-image, inpainting).
struct ImageEditingSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var taskQueue = TaskQueue.shared
    
    let sourceImage: CGImage?
    let maskImage: CGImage?
    
    @State private var prompt: String = ""
    @State private var model: String = ""
    @State private var size: String = ""
    @State private var count: Int = 1
    
    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var editedImages: [CGImage] = []
    
    private let sizes = ["", "1024x1024", "512x512", "auto"]
    
    init(session: EditorSession, sourceImage: CGImage? = nil, maskImage: CGImage? = nil) {
        self.session = session
        self.sourceImage = sourceImage
        self.maskImage = maskImage
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(maskImage != nil ? "Inpainting" : "Image Editing")
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
                                .frame(height: 120)
                                .font(.body)
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
                                Text("Size")
                                Spacer()
                                Picker("", selection: $size) {
                                    ForEach(sizes, id: \.self) { Text($0.isEmpty ? "Original" : $0) }
                                }
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Count")
                                Spacer()
                                Stepper("", value: $count, in: 1...4)
                                    .frame(width: 200)
                            }
                        }
                        
                        Section("Source") {
                            if let source = sourceImage {
                                HStack {
                                    Image(nsImage: NSImage(cgImage: source, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(4)
                                    VStack(alignment: .leading) {
                                        Text("\(source.width) × \(source.height)")
                                            .font(.caption)
                                        Text("Source image loaded")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("No source image")
                                    .foregroundColor(.secondary)
                            }
                            
                            if let mask = maskImage {
                                HStack {
                                    Image(nsImage: NSImage(cgImage: mask, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(4)
                                    VStack(alignment: .leading) {
                                        Text("Mask")
                                            .font(.caption)
                                        Text("Inpainting mode")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Preview
                VStack(spacing: 16) {
                    if editedImages.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No edited images yet")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                                ForEach(Array(editedImages.enumerated()), id: \.offset) { index, image in
                                    Image(nsImage: NSImage(cgImage: image, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(8)
                                        .contextMenu {
                                            Button("Replace Layer") {
                                                replaceLayer(image)
                                            }
                                            Button("Add as New Layer") {
                                                addAsNewLayer(image)
                                            }
                                            Button("Save to Disk…") {
                                                saveToDisk(image)
                                            }
                                        }
                                }
                            }
                            .padding()
                        }
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
                if taskQueue.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Editing…")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(maskImage != nil ? "Inpaint" : "Edit") {
                    edit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.isEmpty || sourceImage == nil || isEditing || taskQueue.isProcessing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func edit() {
        guard let source = sourceImage else { return }
        
        isEditing = true
        errorMessage = nil
        editedImages = []
        
        Task {
            do {
                var parts: [MultipartPart] = []
                
                // Add source image
                if let sourcePart = ImageBridge.multipartPart(for: source, name: "image") {
                    parts.append(sourcePart)
                }
                
                // Add mask if present
                if let mask = maskImage, let maskPart = ImageBridge.multipartPart(for: mask, name: "mask") {
                    parts.append(maskPart)
                }
                
                // Add prompt
                parts.append(.text("prompt", prompt))
                
                // Add model: the field's value, or the capability slot's default, so the endpoint isn't left
                // without its required model when the user typed nothing.
                let resolvedModel = model.isEmpty
                    ? (GatewayConfigurationStore.shared.model(for: .imageEdits) ?? "gpt-image-1")
                    : model
                parts.append(.text("model", resolvedModel))
                
                // Add other parameters
                if !size.isEmpty {
                    parts.append(.text("size", size))
                }
                
                parts.append(.text("n", String(count)))
                parts.append(.text("response_format", "b64_json"))
                
                let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: .imageEdits,
                    parts: parts,
                    as: ImageResponse.self
                )
                
                // Decode images
                for imageData in response.data {
                    if let b64 = imageData.b64_json, let image = ImageBridge.cgImage(fromBase64: b64) {
                        editedImages.append(image)
                    } else if let urlStr = imageData.url, let url = URL(string: urlStr) {
                        let image = try await ImageBridge.downloadImage(from: url)
                        editedImages.append(image)
                    }
                }
                
                isEditing = false
            } catch {
                isEditing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func replaceLayer(_ image: CGImage) {
        if session.replaceActiveLayer(with: image) {
            dismiss()
        } else {
            errorMessage = "Couldn't apply to the active layer. Select a pixel layer first."
        }
    }
    
    private func addAsNewLayer(_ image: CGImage) {
        if session.placeGeneratedImage(image, named: "AI Edit") {
            dismiss()
        } else {
            errorMessage = "Couldn't add the image to the canvas."
        }
    }
    
    private func saveToDisk(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "edited_image.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = ImageBridge.pngData(from: image) {
                try? data.write(to: url)
            }
        }
    }
}
