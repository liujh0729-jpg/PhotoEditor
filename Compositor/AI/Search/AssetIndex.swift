import Foundation

/// One indexed sentence in the asset library: what it says and which project it came from, with the
/// vector the gateway's embedding model gave it.
nonisolated struct AssetIndexEntry: Codable, Equatable, Hashable {
    let projectPath: String
    let text: String
    let vector: [Double]
}

/// The asset search's index: every recent project's layer names and saved image description embedded
/// once, kept as a JSON file beside the app's other support data, and searched by cosine. Re-indexing
/// only asks the gateway about text that isn't in the file yet, so a walk through the recent list is
/// cheap after the first pass.
nonisolated enum AssetIndex {
    /// Where the index lives: Application Support/PhotoCompositor/asset-index.json.
    static var indexURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = support.appendingPathComponent("PhotoCompositor", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("asset-index.json")
    }

    static func load(_ url: URL = indexURL) -> [AssetIndexEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([AssetIndexEntry].self, from: data) else { return [] }
        return entries
    }

    static func save(_ entries: [AssetIndexEntry], to url: URL = indexURL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The sentences one project contributes: its saved image description, and a line per named layer.
    /// Groups carry no pixels to find, so their rows only describe the stack; they're indexed too —
    /// searching "backgrounds" and finding the group that holds them is a hit, not noise.
    static func texts(from manifest: ProjectManifest, project: URL) -> [String] {
        var result: [String] = []
        if let description = manifest.aiDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            result.append("\(project.deletingPathExtension().lastPathComponent): \(description)")
        }
        for layer in manifest.layers {
            let name = layer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            result.append("\(project.deletingPathExtension().lastPathComponent): \(name)")
        }
        return Array(Set(result))
    }

    /// The dot product over the two vectors' lengths; 0 when either is empty, mismatched, or all zeros.
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// The entries nearest the query, best first, at most `limit`; an entry with no similarity at all
    /// (a zero cosine) doesn't make the list.
    static func rank(query: [Double], entries: [AssetIndexEntry], limit: Int = 20) -> [(entry: AssetIndexEntry, score: Double)] {
        entries.map { (entry: $0, score: cosine(query, $0.vector)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// The vectors an answer carries, in the order the texts were sent — the gateway may hand them back
    /// shuffled, and the index must pair each vector with the sentence it describes.
    static func vectors(from response: EmbeddingResponse) -> [[Double]] {
        response.data.sorted { $0.index < $1.index }.map { $0.embedding.map(Double.init) }
    }

    /// The model the embeddings slot names, or the small default the gateway answers with.
    @MainActor static func modelName() -> String {
        GatewayConfigurationStore.shared.model(for: .embeddings) ?? "text-embedding-3-small"
    }

    /// One round trip: the gateway's vectors for `texts`, in the order they were sent.
    @MainActor static func embed(_ texts: [String]) async throws -> [[Double]] {
        let request = EmbeddingRequest(model: modelName(), input: texts, encoding_format: "float", dimensions: nil)
        let response: EmbeddingResponse = try await GatewayClient.shared.request(
            endpoint: .embeddings, body: request, as: EmbeddingResponse.self)
        return vectors(from: response)
    }

    /// Brings the index up to date with `projects`: sentences a project no longer says are dropped,
    /// new ones are embedded in one request per project, and unchanged ones keep their vector. Returns
    /// how many sentences were sent to the gateway. `url` swaps the file in tests; `ask` swaps the
    /// network, so the walk can be verified without a gateway.
    static func reindex(projects: [URL], from url: URL = indexURL,
                        ask: @escaping @MainActor ([String]) async throws -> [[Double]]) async -> Int {
        var entries = load(url)
        let paths = Set(projects.map(\.path))
        // A project that left the recent list leaves the index with it.
        entries.removeAll { !paths.contains($0.projectPath) }
        var asked = 0
        for project in projects {
            let manifest: ProjectManifest?
            if let data = try? Data(contentsOf: project.appendingPathComponent("manifest.json")) {
                manifest = try? JSONDecoder().decode(ProjectManifest.self, from: data)
            } else {
                manifest = nil
            }
            let wanted = manifest.map { texts(from: $0, project: project) } ?? []
            let known = Set(entries.filter { $0.projectPath == project.path }.map(\.text))
            let fresh = wanted.filter { !known.contains($0) }
            // Names the project dropped go, so a renamed layer's old line stops surfacing.
            entries.removeAll { $0.projectPath == project.path && !wanted.contains($0.text) }
            guard !fresh.isEmpty else { continue }
            guard let vectors = try? await ask(fresh), vectors.count == fresh.count else { continue }
            for (text, vector) in zip(fresh, vectors) {
                entries.append(AssetIndexEntry(projectPath: project.path, text: text, vector: vector))
            }
            asked += fresh.count
        }
        save(entries, to: url)
        return asked
    }
}
