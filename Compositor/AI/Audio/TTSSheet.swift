import SwiftUI
import AVFoundation

/// Sheet for text-to-speech synthesis.
struct TTSSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var text: String = ""
    @State private var model: String = ""
    @State private var voice: String = "alloy"
    @State private var speed: Double = 1.0
    @State private var responseFormat: String = "mp3"
    
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var audioData: Data?
    @State private var audioPlayer: AVPlayer?
    
    private let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
    private let formats = ["mp3", "opus", "aac", "flac"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Text-to-Speech")
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
                        Section("Text") {
                            TextEditor(text: $text)
                                .frame(height: 200)
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
                                Text("Voice")
                                Spacer()
                                Picker("", selection: $voice) {
                                    ForEach(voices, id: \.self) { Text($0.capitalized) }
                                }
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Speed")
                                Spacer()
                                Slider(value: $speed, in: 0.25...4.0)
                                    .frame(width: 150)
                                Text(String(format: "%.2fx", speed))
                                    .frame(width: 50)
                            }
                            
                            HStack {
                                Text("Format")
                                Spacer()
                                Picker("", selection: $responseFormat) {
                                    ForEach(formats, id: \.self) { Text($0.uppercased()) }
                                }
                                .frame(width: 200)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Preview/Player
                VStack(spacing: 16) {
                    if let data = audioData {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("Audio ready")
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 16) {
                                Button(action: { play() }) {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .disabled(audioPlayer == nil)
                                
                                Button(action: { stop() }) {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                                .disabled(audioPlayer == nil)
                                
                                Button(action: { saveToDisk(data) }) {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No audio generated yet")
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
                if isGenerating {
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
                .disabled(text.isEmpty || isGenerating)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func generate() {
        isGenerating = true
        errorMessage = nil
        audioData = nil
        audioPlayer = nil
        
        Task {
            do {
                let request = SpeechRequest(
                    model: model.isEmpty ? (GatewayConfigurationStore.shared.model(for: .audioSpeech) ?? "tts-1") : model,
                    input: text,
                    voice: voice,
                    response_format: responseFormat,
                    speed: speed
                )
                
                let data = try await GatewayClient.shared.downloadBinary(
                    endpoint: .audioSpeech,
                    body: request
                )
                
                audioData = data
                
                // Create temporary file for playback
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tts_output.\(responseFormat)")
                try data.write(to: tempURL)
                
                audioPlayer = AVPlayer(url: tempURL)
                
                isGenerating = false
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func play() {
        audioPlayer?.play()
    }
    
    private func stop() {
        audioPlayer?.pause()
        audioPlayer?.seek(to: .zero)
    }
    
    private func saveToDisk(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: responseFormat) ?? .data]
        panel.nameFieldStringValue = "speech.\(responseFormat)"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
