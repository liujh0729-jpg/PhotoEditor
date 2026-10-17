import SwiftUI
import UniformTypeIdentifiers

/// Search Assets…: asks the embeddings model what the query means and answers with the projects whose
/// layers and saved descriptions say something near it. The index is built once from the recent
/// projects and only grows for the sentences it hasn't heard before.
struct AssetSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Opens a project the search found, through the controller that owns the document windows.
    let open: (URL) -> Void

    @State private var query = ""
    @State private var results: [(entry: AssetIndexEntry, score: Double)] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search Assets…")
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

            // The one-line question, and the button that builds the index the first time.
            HStack(spacing: 8) {
                TextField("What are you looking for?", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                    .disabled(isWorking)
                Button("Search") { search() }
                    .disabled(query.isEmpty || isWorking)
                Button("Index Recent Projects") { index() }
                    .disabled(isWorking)
            }
            .padding()

            Divider()

            // The matches, nearest first; clicking one opens its project.
            VStack(spacing: 0) {
                if isWorking {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(errorMessage ?? "Nothing indexed yet. Index the recent projects, then ask.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(results, id: \.entry) { hit in
                        Button(action: { open(URL(fileURLWithPath: hit.entry.projectPath)) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sentence(hit.entry))
                                    .lineLimit(1)
                                Text(hit.entry.projectPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            HStack {
                Text("The model learns what each project's layers are called; only the words go to the gateway, never the pictures.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 300, alignment: .leading)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 620, height: 460)
        .background(Color(white: 0.14))
    }

    /// The match without its "Project name: " lead; the path line below already names the project.
    private func sentence(_ entry: AssetIndexEntry) -> String {
        let stem = URL(fileURLWithPath: entry.projectPath).deletingPathExtension().lastPathComponent
        let lead = "\(stem): "
        return entry.text.hasPrefix(lead) ? String(entry.text.dropFirst(lead.count)) : entry.text
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let vectors = try await AssetIndex.embed([text])
                guard let queryVector = vectors.first else { throw GatewayClientError.invalidResponse }
                results = AssetIndex.rank(query: queryVector, entries: AssetIndex.load())
                isWorking = false
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// One walk through the recent projects; the sentences already in the index ride along untouched.
    private func index() {
        isWorking = true
        errorMessage = nil
        let projects = RecentProjects.shared.urls
        Task {
            let asked = await AssetIndex.reindex(projects: projects) { texts in
                try await AssetIndex.embed(texts)
            }
            results = []
            isWorking = false
            if projects.isEmpty {
                errorMessage = "There are no recent projects to index."
            } else if asked == 0 && AssetIndex.load().isEmpty {
                errorMessage = "Nothing new to index."
            }
        }
    }
}
