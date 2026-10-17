import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Auto-Tidy: how the decision model's loose answer turns into concrete rename/group steps, and how those
/// steps land on the document. No gateway is called — the answer is handed over as JSON the same way the
/// real response decodes.
@MainActor
struct AutoTidyTests {
    private func layer(_ id: UUID, _ name: String) -> ImageLayer {
        ImageLayer(id: id, asset: nil, name: name, isVisible: true,
                   transform: LayerTransform(origin: .zero, size: CGSize(width: 10, height: 10)))
    }

    private func response(_ json: String) throws -> SystemOneResponse {
        try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
    }

    @Test func renamesOnlyLandOnRealLayersAndOnlyWhenTheNameChanges() throws {
        let a = UUID(), b = UUID()
        let layers = [layer(a, "Layer 1"), layer(b, "Background")]
        let json = """
        {"answers": {"renames": [
            {"layerId": "\(a.uuidString)", "name": "Sky"},
            {"layerId": "\(b.uuidString)", "name": "Background"},
            {"layerId": "\(UUID().uuidString)", "name": "Ghost"}
        ]}}
        """
        let suggestions = AutoTidy.suggestions(from: try response(json), layers: layers)
        // The no-op rename and the id that isn't a layer both drop.
        #expect(suggestions.count == 1)
        guard case .rename(let id, let to)? = suggestions.first?.kind else { Issue.record("expected a rename"); return }
        #expect(id == a)
        #expect(to == "Sky")
    }

    @Test func groupsNeedTwoRealLayersAndKeepDocumentOrder() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let layers = [layer(a, "eyes"), layer(b, "nose"), layer(c, "sky")]
        let json = """
        {"answers": {"groups": [
            {"name": "Face", "layerIds": ["\(c.uuidString)", "\(a.uuidString)", "\(b.uuidString)", "\(a.uuidString)"]},
            {"name": "Alone", "layerIds": ["\(a.uuidString)"]}
        ]}}
        """
        let suggestions = AutoTidy.suggestions(from: try response(json), layers: layers)
        #expect(suggestions.count == 1) // The one-layer group is dropped.
        guard case .group(let name, let ids)? = suggestions.first?.kind else { Issue.record("expected a group"); return }
        #expect(name == "Face")
        #expect(ids == [a, b, c]) // Re-sorted to document order, deduped.
    }

    @Test func alternateKeySpellingsStillParse() throws {
        let a = UUID(), b = UUID()
        let layers = [layer(a, "Layer 1"), layer(b, "Layer 2")]
        let json = """
        {"answers": {"rename": [{"id": "\(a.uuidString)", "newName": "Front"}],
                     "grouping": [{"name": "Pair", "layers": ["\(a.uuidString)", "\(b.uuidString)"]}]}}
        """
        let suggestions = AutoTidy.suggestions(from: try response(json), layers: layers)
        #expect(suggestions.count == 2)
    }

    @Test func emptyOrMissingAnswersGiveNothing() throws {
        let layers = [layer(UUID(), "Layer 1")]
        #expect(AutoTidy.suggestions(from: try response("{}"), layers: layers).isEmpty)
        #expect(AutoTidy.suggestions(from: try response(#"{"answers": null}"#), layers: layers).isEmpty)
    }

    @Test func applyingSuggestionsRenamesAndGroupsUndoably() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        session.addBlankLayer()
        let first = try #require(session.activeLayerID)
        session.addBlankLayer()
        let second = try #require(session.activeLayerID)

        let rename = TidySuggestion(kind: .rename(layer: first, to: "Ground"))
        let group = TidySuggestion(kind: .group(name: "Scenery", layers: [first, second]))
        let applied = session.applyTidySuggestions([rename, group])
        #expect(applied == 2)

        // The folder holds both, named as suggested; the rename happened before grouping.
        let groupID = try #require(session.activeLayerID)
        #expect(session.activeLayer?.isGroup == true)
        #expect(session.activeLayer?.name == "Scenery")
        let parentOf = { (id: UUID) in session.document?.layers.first(where: { $0.id == id })?.parentID }
        #expect(parentOf(first) == groupID)
        #expect(parentOf(second) == groupID)
        #expect(session.document?.layers.first(where: { $0.id == first })?.name == "Ground")

        // The tidy's steps ride undo: unwinding them takes the folder back off (leaving the two blank layers).
        #expect(session.document?.layers.count == 3) // folder + two children
        session.undo() // undo the folder's rename
        session.undo() // undo the grouping
        #expect(session.document?.layers.count == 2)
        #expect(session.document?.layers.contains { $0.isGroup } == false)
    }

    @Test func applyingRefusesWhenNothingIsEditable() {
        let session = EditorSession()
        // No document: the guard holds and nothing lands.
        let applied = session.applyTidySuggestions([TidySuggestion(kind: .rename(layer: UUID(), to: "X"))])
        #expect(applied == 0)
    }
}
