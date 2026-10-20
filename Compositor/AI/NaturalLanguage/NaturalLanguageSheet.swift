import SwiftUI

/// Sheet for natural language editing commands.
struct NaturalLanguageSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    
    @State private var input: String = ""
    @State private var history: [HistoryEntry] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var pendingIntent: EditingIntent?
    @State private var showingConfirmation = false
    
    struct HistoryEntry: Identifiable {
        let id = UUID()
        let input: String
        let intent: EditingIntent
        let executed: Bool
        /// The engine filled a parameter the intent left out from what this action usually runs with.
        let preferred: Bool
        let timestamp: Date
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Natural Language Editing")
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
            VStack(spacing: 16) {
                // Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What would you like to do?")
                        .font(.headline)
                    
                    HStack {
                        TextField("e.g., 'Make it warmer', 'Select the subject', 'Increase brightness'", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { execute() }
                        
                        Button("Execute") {
                            execute()
                        }
                        .disabled(input.isEmpty || isProcessing)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                
                // History
                if !history.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(.headline)
                        
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(history.reversed()) { entry in
                                    HistoryRow(entry: entry)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .background(Color(white: 0.14))
        .alert("Confirm Action", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingIntent = nil
            }
            Button("Execute", role: .destructive) {
                if let intent = pendingIntent {
                    Task { await executeIntent(intent) }
                }
            }
        } message: {
            if let intent = pendingIntent {
                Text(intent.description)
            }
        }
    }
    
    private func execute() {
        guard !input.isEmpty else { return }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let context = EditingContext(
                    activeLayerName: session.activeLayer?.name,
                    hasSelection: session.selection != nil,
                    layerCount: session.document?.layers.count ?? 0
                )
                
                let intent = try await IntentRecognition.shared.recognize(
                    input: input,
                    context: context
                )
                
                let entry = HistoryEntry(
                    input: input,
                    intent: intent,
                    executed: false,
                    preferred: false,
                    timestamp: Date()
                )
                history.append(entry)
                
                if intent.requiresConfirmation || intent.isDestructive {
                    pendingIntent = intent
                    showingConfirmation = true
                } else {
                    await executeIntent(intent)
                }
                
                isProcessing = false
                input = ""
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func executeIntent(_ intent: EditingIntent) async {
        let preferred = intent.usedPreference
        guard await session.applyAIIntent(intent) else {
            errorMessage = "Can't apply \(intent.description) right now."
            return
        }
        // The run is a habit worth remembering: every number that answered goes into the tally.
        PreferenceStore.shared.record(intent)
        if let index = history.lastIndex(where: { $0.intent.action == intent.action && !$0.executed }) {
            history[index] = HistoryEntry(
                input: history[index].input,
                intent: history[index].intent,
                executed: true,
                preferred: preferred,
                timestamp: history[index].timestamp
            )
        }
    }
}

/// A single history entry row.
struct HistoryRow: View {
    let entry: NaturalLanguageSheet.HistoryEntry
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.executed ? "checkmark.circle.fill" : "clock")
                .foregroundColor(entry.executed ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.input)
                    .font(.body)
                
                Text(entry.intent.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if entry.preferred {
                    // Why a command with no numbers in it still knew what to set.
                    Text("Because you often do this")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            Text(entry.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(white: 0.18))
        .cornerRadius(6)
    }
}
