import SwiftUI
import UniformTypeIdentifiers

/// Sheet for generating videos from text or images.
struct VideoGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var taskQueue = TaskQueue.shared
    
    let sourceImage: CGImage?
    
    @State private var prompt: String = ""
    @State private var model: String = ""
    @State private var duration: Int = 5
    @State private var resolution: String = "720p"
    @State private var generateAudio: Bool = false
    
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var taskID: String?
    @State private var currentTask: GatewayTask?
    
    private let resolutions = ["480p", "720p", "1080p"]
    
    init(sourceImage: CGImage? = nil) {
        self.sourceImage = sourceImage
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate Video")
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
                                Text("Duration")
                                Spacer()
                                Stepper("\(duration)s", value: $duration, in: 2...10)
                                    .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Resolution")
                                Spacer()
                                Picker("", selection: $resolution) {
                                    ForEach(resolutions, id: \.self) { Text($0) }
                                }
                                .frame(width: 200)
                            }
                            
                            Toggle("Generate Audio", isOn: $generateAudio)
                        }
                        
                        if let source = sourceImage {
                            Section("Source") {
                                HStack {
                                    Image(nsImage: NSImage(cgImage: source, size: .zero))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(4)
                                    VStack(alignment: .leading) {
                                        Text("Image-to-Video")
                                            .font(.caption)
                                        Text("Animating source image")
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
                
                // Right: Status/Preview
                VStack(spacing: 16) {
                    if let task = currentTask {
                        VStack(spacing: 12) {
                            switch task.status {
                            case .queued:
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Queued…")
                                    .foregroundColor(.secondary)
                            case .inProgress:
                                ProgressView(value: task.progress ?? 0)
                                    .frame(width: 200)
                                Text("Generating… \(Int((task.progress ?? 0) * 100))%")
                                    .foregroundColor(.secondary)
                            case .completed:
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                Text("Video ready!")
                                    .foregroundColor(.secondary)
                                if !task.outputURLs.isEmpty {
                                    Button("Download Video") {
                                        downloadVideo(task.outputURLs[0])
                                    }
                                    Button("Save Live Photo…") {
                                        saveLivePhoto(task.outputURLs[0])
                                    }
                                    .help("Export the first frame and the clip as a Live Photo pair.")
                                }
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.red)
                                Text(task.error ?? "Generation failed")
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No video generated yet")
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
                if isGenerating, let id = taskID {
                    Button("Cancel Task") {
                        taskQueue.cancelTask(id)
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
        .onChange(of: taskQueue.tasks) { _, tasks in
            if let id = taskID {
                currentTask = tasks.first { $0.id == id }
            }
        }
    }
    
    private func generate() {
        isGenerating = true
        errorMessage = nil
        currentTask = nil
        
        Task {
            do {
                var request = VideoGenerationRequest(
                    model: model.isEmpty ? (GatewayConfigurationStore.shared.model(for: .video) ?? "sora") : model,
                    prompt: prompt,
                    duration: duration,
                    resolution: resolution,
                    generate_audio: generateAudio
                )
                
                // Add source image if present
                if let source = sourceImage, let b64 = ImageBridge.base64(from: source) {
                    request.image = b64
                }
                
                _ = try await taskQueue.submitTask(
                    endpoint: .video,
                    body: request,
                    onCreate: { response in
                        taskID = response.taskID
                    }
                )
                
                isGenerating = false
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func downloadVideo(_ url: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "generated_video.mp4"
        
        if panel.runModal() == .OK, let saveURL = panel.url {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    try data.write(to: saveURL)
                } catch {
                    errorMessage = "Failed to download: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Pulls the clip to a temp file, lifts its first frame, and writes the still + movie pair — a Live
    /// Photo Photos reunites — into a folder the person picks. Filing straight into the library is the last
    /// manual step (drop the folder onto Photos), since that needs the photo-library entitlement.
    private func saveLivePhoto(_ url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("livephoto-\(UUID().uuidString).mov")
                try data.write(to: temp)
                defer { try? FileManager.default.removeItem(at: temp) }
                guard await LivePhoto.export(from: temp, to: folder) != nil else {
                    errorMessage = "The clip had no frame to lift into a Live Photo."
                    isGenerating = false
                    return
                }
                isGenerating = false
            } catch {
                isGenerating = false
                errorMessage = "Failed to save Live Photo: \(error.localizedDescription)"
            }
        }
    }
}
