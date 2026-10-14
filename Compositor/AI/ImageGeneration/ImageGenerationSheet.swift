import SwiftUI
import UniformTypeIdentifiers

/// Sheet for generating images from text prompts.
struct ImageGenerationSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var taskQueue = TaskQueue.shared
    
    @State private var prompt: String = ""
    @State private var negativePrompt: String = ""
    @State private var model: String = ""
    @State private var size: String = "1024x1024"
    @State private var quality: String = "standard"
    @State private var count: Int = 1
    @State private var style: String = ""
    
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedImages: [CGImage] = []
    
    private let sizes = ["1024x1024", "1024x1792", "1792x1024", "512x512", "768x768"]
    private let qualities = ["standard", "hd"]
    private let styles = ["", "vivid", "natural"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate Image")
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
                            
                            TextField("Negative prompt (optional)", text: $negativePrompt)
                                .textFieldStyle(.roundedBorder)
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
                                    ForEach(sizes, id: \.self) { Text($0) }
                                }
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Quality")
                                Spacer()
                                Picker("", selection: $quality) {
                                    ForEach(qualities, id: \.self) { Text($0.capitalized) }
                                }
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Style")
                                Spacer()
                                Picker("", selection: $style) {
                                    Text("Default").tag("")
                                    ForEach(styles.filter { !$0.isEmpty }, id: \.self) { Text($0.capitalized) }
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
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Preview
                VStack(spacing: 16) {
                    if generatedImages.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No images generated yet")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                                ForEach(Array(generatedImages.enumerated()), id: \.offset) { index, image in
                                    Image(nsImage: NSImage(cgImage: image, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(8)
                                        .contextMenu {
                                            Button("Use as Layer") {
                                                useAsLayer(image)
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
                        Text("Generating…")
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
                .disabled(prompt.isEmpty || isGenerating || taskQueue.isProcessing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func generate() {
        isGenerating = true
        errorMessage = nil
        generatedImages = []
        
        Task {
            do {
                var request = ImageGenerationRequest(
                    model: model.isEmpty ? (GatewayConfigurationStore.shared.model(for: .imageGeneration) ?? "dall-e-3") : model,
                    prompt: prompt,
                    n: count,
                    size: size,
                    quality: quality
                )
                
                if !style.isEmpty {
                    request.style = style
                }
                
                if !negativePrompt.isEmpty {
                    request.negative_prompt = negativePrompt
                }
                
                request.response_format = "b64_json"
                
                let response: ImageResponse = try await GatewayClient.shared.request(
                    endpoint: .imageGeneration,
                    body: request,
                    as: ImageResponse.self
                )
                
                // Decode images
                for imageData in response.data {
                    if let b64 = imageData.b64_json, let image = ImageBridge.cgImage(fromBase64: b64) {
                        generatedImages.append(image)
                    } else if let urlStr = imageData.url, let url = URL(string: urlStr) {
                        let image = try await ImageBridge.downloadImage(from: url)
                        generatedImages.append(image)
                    }
                }
                
                isGenerating = false
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func useAsLayer(_ image: CGImage) {
        if session.placeGeneratedImage(image, named: "AI Image") {
            dismiss()
        } else {
            errorMessage = "Couldn't add the image to the canvas."
        }
    }
    
    private func saveToDisk(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated_image.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = ImageBridge.pngData(from: image) {
                try? data.write(to: url)
            }
        }
    }
}
