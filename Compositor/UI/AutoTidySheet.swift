import SwiftUI

/// The Auto-Tidy sheet: the decision model reads the layer tree and proposes names and folders; the person
/// ticks the ones they like and applies them, each a step ⌘Z can undo. Nothing on the canvas changes until
/// Apply is pressed, so the list is a preview, not a promise.
struct AutoTidySheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [TidySuggestion] = []
    @State private var rejected: Set<TidySuggestion.ID> = []
    @State private var reasoning: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var chosen: [TidySuggestion] { suggestions.filter { !rejected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Auto-Tidy…")
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

            // The proposed changes, each ticked unless cleared.
            VStack(spacing: 0) {
                if isWorking {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Deciding…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suggestions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(errorMessage ?? "The model sees nothing worth renaming or grouping.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        if let reasoning {
                            Text(reasoning)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(suggestions) { suggestion in
                            Toggle(isOn: binding(for: suggestion)) {
                                Label {
                                    Text(suggestion.label)
                                } icon: {
                                    Image(systemName: icon(of: suggestion))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            HStack {
                Text("Only the layer names and their place in the tree go to the model, never the pictures.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 300, alignment: .leading)
                Spacer()
                Button("Apply") {
                    apply()
                }
                .disabled(chosen.isEmpty || isWorking)
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 560, height: 440)
        .background(Color(white: 0.14))
        .task { await suggest() }
    }

    private func binding(for suggestion: TidySuggestion) -> Binding<Bool> {
        Binding(
            get: { !rejected.contains(suggestion.id) },
            set: { on in if on { rejected.remove(suggestion.id) } else { rejected.insert(suggestion.id) } }
        )
    }

    private func icon(of suggestion: TidySuggestion) -> String {
        switch suggestion.kind {
        case .rename: return "pencil"
        case .group: return "folder"
        }
    }

    private func suggest() async {
        guard let document = session.document, !document.layers.isEmpty else {
            errorMessage = "There are no layers to tidy."
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            let response = try await AutoTidy.suggest(over: document.layers,
                                                     width: document.width, height: document.height)
            suggestions = AutoTidy.suggestions(from: response, layers: document.layers)
            reasoning = response.reasoning
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func apply() {
        session.applyTidySuggestions(chosen)
        dismiss()
    }
}
