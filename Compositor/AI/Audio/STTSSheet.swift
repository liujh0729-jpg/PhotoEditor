import SwiftUI
import AVFoundation

/// Sheet for speech-to-text transcription.
struct STTSSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var audioFileURL: URL?
    @State private var model: String = ""
    @State private var language: String = ""
    @State private var prompt: String = ""
    @State private var responseFormat: String = "json"
    
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @State private var transcription: String?
    @State private var segments: [TranscriptionResponse.TranscriptionSegment] = []
    
    private let formats = ["json", "text", "srt", "vtt", "verbose_json"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Speech-to-Text")
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
                        Section("Audio File") {
                            Button("Choose Audio File…") {
                                chooseAudioFile()
                            }
                            
                            if let url = audioFileURL {
                                HStack {
                                    Image(systemName: "doc.audio")
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                                Text("Language")
                                Spacer()
                                TextField("Auto-detect", text: $language)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                            
                            TextField("Prompt (optional)", text: $prompt)
                                .textFieldStyle(.roundedBorder)
                            
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
                
                // Right: Result
                VStack(spacing: 16) {
                    if let text = transcription {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transcription")
                                .font(.headline)
                            
                            ScrollView {
                                Text(text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                            
                            if !segments.isEmpty {
                                Divider()
                                
                                Text("Segments")
                                    .font(.headline)
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                            HStack(alignment: .top) {
                                                Text(formatTime(segment.start ?? 0))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 60, alignment: .leading)
                                                Text(segment.text ?? "")
                                                    .font(.body)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 150)
                            }
                            
                            HStack {
                                Button("Copy Text") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                                
                                Button("Save to Disk…") {
                                    saveToDisk(text)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No transcription yet")
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
                if isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Transcribing…")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Transcribe") {
                    transcribe()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(audioFileURL == nil || isTranscribing)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(Color(white: 0.14))
    }
    
    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            audioFileURL = panel.url
        }
    }
    
    /// Picks the multipart Content-Type from the file's extension. Whisper and friends key their decoding off
    /// this field; a hard-coded "audio/mpeg" mislabels a .wav or .m4a upload.
    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg", "oga", "opus": return "audio/ogg"
        case "webm": return "audio/webm"
        case "aiff", "aif", "caf": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }
    
    private func transcribe() {
        guard let fileURL = audioFileURL else { return }
        
        isTranscribing = true
        errorMessage = nil
        transcription = nil
        segments = []
        
        Task {
            do {
                let audioData = try Data(contentsOf: fileURL)
                
                var parts: [MultipartPart] = []
                parts.append(.data("file", audioData, filename: fileURL.lastPathComponent, mimeType: Self.mimeType(for: fileURL)))
                parts.append(.text("model", model.isEmpty ? (GatewayConfigurationStore.shared.model(for: .audioTranscriptions) ?? "whisper-1") : model))
                
                if !language.isEmpty {
                    parts.append(.text("language", language))
                }
                
                if !prompt.isEmpty {
                    parts.append(.text("prompt", prompt))
                }
                
                parts.append(.text("response_format", responseFormat))
                
                let response: TranscriptionResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: .audioTranscriptions,
                    parts: parts,
                    as: TranscriptionResponse.self
                )
                
                transcription = response.text
                segments = response.segments ?? []
                
                isTranscribing = false
            } catch {
                isTranscribing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func saveToDisk(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
