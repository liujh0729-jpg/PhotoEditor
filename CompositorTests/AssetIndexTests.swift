import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// The asset search's index: the pure math (cosine, ranking), the sentences a project contributes,
/// and the re-index walk with a stubbed gateway — no real embeddings request is made here.
struct AssetIndexTests {
    private func entry(_ project: String, _ text: String, _ vector: [Double]) -> AssetIndexEntry {
        AssetIndexEntry(projectPath: project, text: text, vector: vector)
    }

    /// Cosines carry float rounding, so direction checks compare with a tolerance.
    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func cosineOfSimilarVectors() {
        #expect(near(AssetIndex.cosine([1, 0], [1, 0]), 1))
        #expect(AssetIndex.cosine([1, 0], [0, 1]) == 0)
        // Same direction, different length.
        #expect(near(AssetIndex.cosine([2, 1], [4, 2]), 1))
    }

    @Test func cosineOfMismatchedOrEmptyVectorsIsZero() {
        #expect(AssetIndex.cosine([1, 2], [1]) == 0)
        #expect(AssetIndex.cosine([], []) == 0)
        #expect(AssetIndex.cosine([0, 0], [1, 1]) == 0) // Zero norm: nothing to compare.
    }

    @Test func rankOrdersByScoreAndDropsZeroes() {
        let entries = [
            entry("/a.comp", "far", [3, 4]),
            entry("/b.comp", "near", [4, 3]),
            entry("/c.comp", "orthogonal", [0, 1]),
        ]
        let hits = AssetIndex.rank(query: [1, 0], entries: entries)
        #expect(hits.map(\.entry.text) == ["near", "far"])
        #expect(hits[0].score > hits[1].score)
    }

    @Test func rankHonorsTheLimit() {
        let entries = (0..<30).map { entry("/\($0).comp", "layer \($0)", [1, Double($0) / 100]) }
        let hits = AssetIndex.rank(query: [1, 0], entries: entries, limit: 5)
        #expect(hits.count == 5)
    }

    @Test func textsCoversDescriptionAndLayerNamesWithoutDuplicates() {
        let manifest = ProjectManifest(
            documentID: UUID(), width: 10, height: 10, activeLayerID: nil,
            layers: [
                ProjectLayerRecord(id: UUID(), name: "Sky", isVisible: true,
                                   transform: LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1)),
                                   imageFile: nil),
                ProjectLayerRecord(id: UUID(), name: "Sky", isVisible: true, // Same name twice: one line.
                                   transform: LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1)),
                                   imageFile: nil),
                ProjectLayerRecord(id: UUID(), name: "  ", isVisible: true, // Blank names don't count.
                                   transform: LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1)),
                                   imageFile: nil),
            ],
            aiDescription: "A dusk skyline.")
        let texts = AssetIndex.texts(from: manifest, project: URL(fileURLWithPath: "/tmp/Dusk.comp"))
        #expect(texts.contains("Dusk: A dusk skyline."))
        #expect(texts.contains("Dusk: Sky"))
        #expect(texts.count == 2)
    }

    @Test func vectorsComeBackInSendOrderEvenIfTheGatewayShuffles() {
        let response = EmbeddingResponse(
            data: [
                EmbeddingResponse.EmbeddingData(object: "embedding", index: 1, embedding: [0.5, 0.5]),
                EmbeddingResponse.EmbeddingData(object: "embedding", index: 0, embedding: [1, 0]),
            ],
            model: "text-embedding-3-small", usage: nil)
        let vectors = AssetIndex.vectors(from: response)
        #expect(vectors[0] == [1, 0])
        #expect(vectors[1] == [0.5, 0.5])
    }

    /// Writes a `.comp` folder with a manifest into a temporary directory, for the re-index walk.
    private func makeProject(stem: String, layers: [String], description: String? = nil) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-index-tests-\(UUID().uuidString)")
            .appendingPathComponent("\(stem).comp")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest = ProjectManifest(
            documentID: UUID(), width: 10, height: 10, activeLayerID: nil,
            layers: layers.enumerated().map { _, name in
                ProjectLayerRecord(id: UUID(), name: name, isVisible: true,
                                   transform: LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1)),
                                   imageFile: nil)
            },
            aiDescription: description)
        let data = try! JSONEncoder().encode(manifest)
        try! data.write(to: url.appendingPathComponent("manifest.json"))
        return url
    }

    private func indexURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("asset-index-\(UUID().uuidString).json")
    }

    @MainActor @Test func reindexAsksOnceForNewSentencesAndNothingForKnownOnes() async {
        let project = makeProject(stem: "Dusk", layers: ["Sky", "Ground"], description: "A dusk skyline.")
        let url = indexURL()
        final class Box: @unchecked Sendable { var calls: [[String]] = [] }
        let box = Box()
        let asked = await AssetIndex.reindex(projects: [project], from: url) { texts in
            box.calls.append(texts)
            return texts.map { _ in [1.0, 0.0] }
        }
        #expect(asked == 3)
        #expect(box.calls.count == 1)
        #expect(Set(box.calls[0]) == Set(["Dusk: Sky", "Dusk: Ground", "Dusk: A dusk skyline."]))
        // Second walk: everything is known, so the gateway isn't asked again.
        let again = await AssetIndex.reindex(projects: [project], from: url) { texts in
            box.calls.append(texts)
            return texts.map { _ in [1.0, 0.0] }
        }
        #expect(again == 0)
        #expect(box.calls.count == 1)
        #expect(AssetIndex.load(url).count == 3)
    }

    @MainActor @Test func reindexDropsSentencesTheProjectStoppedSaying() async {
        let project = makeProject(stem: "Dusk", layers: ["Sky"])
        let url = indexURL()
        _ = await AssetIndex.reindex(projects: [project], from: url) { texts in
            texts.map { _ in [1.0, 0.0] }
        }
        #expect(AssetIndex.load(url).map(\.text) == ["Dusk: Sky"])
        // The layer is renamed; the old line stops surfacing.
        let renamed = makeProjectWithLayers(project: project, layers: ["Clouds"])
        let asked = await AssetIndex.reindex(projects: [renamed], from: url) { texts in
            #expect(texts == ["Dusk: Clouds"])
            return texts.map { _ in [0.0, 1.0] }
        }
        #expect(asked == 1)
        #expect(AssetIndex.load(url).map(\.text) == ["Dusk: Clouds"])
    }

    @MainActor @Test func reindexDropsProjectsThatLeftTheRecentList() async {
        let kept = makeProject(stem: "Kept", layers: ["Sky"])
        let gone = makeProject(stem: "Gone", layers: ["Ground"])
        let url = indexURL()
        _ = await AssetIndex.reindex(projects: [kept, gone], from: url) { texts in
            texts.map { _ in [1.0] }
        }
        #expect(AssetIndex.load(url).count == 2)
        _ = await AssetIndex.reindex(projects: [kept], from: url) { texts in
            texts.map { _ in [1.0] }
        }
        let entries = AssetIndex.load(url)
        #expect(entries.count == 1)
        #expect(entries[0].projectPath == kept.path)
    }

    @MainActor @Test func reindexKeepsTheOldIndexWhenTheGatewayRefuses() async {
        let project = makeProject(stem: "Dusk", layers: ["Sky"])
        let url = indexURL()
        let asked = await AssetIndex.reindex(projects: [project], from: url) { _ in
            throw GatewayClientError.invalidResponse
        }
        #expect(asked == 0)
        #expect(AssetIndex.load(url).isEmpty)
    }

    /// Rewrites a project folder's manifest with new layer names, keeping its URL.
    private func makeProjectWithLayers(project: URL, layers: [String]) -> URL {
        let manifest = ProjectManifest(
            documentID: UUID(), width: 10, height: 10, activeLayerID: nil,
            layers: layers.map { name in
                ProjectLayerRecord(id: UUID(), name: name, isVisible: true,
                                   transform: LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1)),
                                   imageFile: nil)
            })
        let data = try! JSONEncoder().encode(manifest)
        try! data.write(to: project.appendingPathComponent("manifest.json"))
        return project
    }
}
