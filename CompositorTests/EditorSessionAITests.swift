import AppKit
import Testing
@testable import Compositor

/// The canvas side of the AI features: dropping a generated image, replacing the active layer, and running
/// natural-language intents through the session's own edits. Kept out of the sheets so the behavior is testable
/// without any UI or gateway.
@MainActor
struct EditorSessionAITests {
    /// A solid gray image of the given size, standing in for whatever the gateway returns.
    private func solidImage(width: Int, height: Int) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func session(withLayerNamed name: String, width: Int = 200, height: Int = 200) throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: width, height: height)
        session.insert(ImportedImage(image: try solidImage(width: width, height: height), thumbnail: try solidImage(width: 20, height: 20), name: name))
        return session
    }

    @Test func placeGeneratedImageAddsANamedLayer() throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        session.placeGeneratedImage(try solidImage(width: 120, height: 80), named: "AI Image")
        let layer = try #require(session.activeLayer)
        #expect(session.document?.layers.count == 1)
        #expect(layer.name == "AI Image")
        #expect(layer.asset?.image.width == 120 && layer.asset?.image.height == 80)
    }

    @Test func replaceActiveLayerSwapsPixelsAndKeepsTheName() throws {
        let session = try session(withLayerNamed: "Original")
        session.replaceActiveLayer(with: try solidImage(width: 100, height: 50))
        let layer = try #require(session.activeLayer)
        #expect(layer.name == "Original")
        #expect(session.document?.layers.count == 1)
        #expect(layer.asset?.image.width == 100)
        // The layer's transform resizes to the new bitmap so the pixels aren't stretched back to the old box.
        #expect(layer.transform.size == CGSize(width: 100, height: 50))
        // The swap folds into history like any other pixel edit, so it undoes back to the old pixels.
        session.undo()
        #expect(session.activeLayer?.asset?.image.width == 200)
    }

    @Test func replaceActiveLayerFreezesAnUnplacedMask() throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        session.addLayerMask(revealing: true)
        // The mask has no placement of its own, so it follows the layer transform until the swap pins it.
        #expect(session.activeLayer?.mask?.placement == nil)
        session.replaceActiveLayer(with: try solidImage(width: 120, height: 90))
        let frozen = try #require(session.activeLayer?.mask?.placement)
        #expect(frozen.size == CGSize(width: 200, height: 200))
    }

    @Test func renameIntentTargetsTheActiveLayer() throws {
        let session = try session(withLayerNamed: "Before")
        let intent = EditingIntent(action: .renameLayer, parameters: ["name": AnyCodable("After")])
        #expect(session.applyAIIntent(intent))
        #expect(session.activeLayer?.name == "After")
    }

    @Test func duplicateAndDeleteIntentsChangeTheLayerStack() throws {
        let session = try session(withLayerNamed: "Layer")
        #expect(session.applyAIIntent(EditingIntent(action: .duplicateLayer)))
        #expect(session.document?.layers.count == 2)
        #expect(session.applyAIIntent(EditingIntent(action: .deleteLayer)))
        #expect(session.document?.layers.count == 1)
    }

    @Test func addMaskIntentRunsOnceThenRefuses() throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        #expect(session.applyAIIntent(EditingIntent(action: .addMask)))
        #expect(session.activeLayer?.mask != nil)
        // The layer already has a mask, so the intent no longer applies.
        #expect(!session.applyAIIntent(EditingIntent(action: .addMask)))
    }

    @Test func selectionIntentsFollowTheCurrentSelection() throws {
        let session = try session(withLayerNamed: "Layer")
        #expect(session.applyAIIntent(EditingIntent(action: .deselect)))
        // There's nothing to invert without a selection.
        #expect(!session.applyAIIntent(EditingIntent(action: .invertSelection)))
    }

    @Test func layerIntentsDoNothingWithoutAnActiveLayer() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100) // Empty: no layers yet.
        #expect(!session.applyAIIntent(EditingIntent(action: .deleteLayer)))
        #expect(!session.applyAIIntent(EditingIntent(action: .duplicateLayer)))
        #expect(!session.applyAIIntent(EditingIntent(action: .renameLayer, parameters: ["name": AnyCodable("X")])))
    }

    @Test func unknownIntentsAreReportedAsNotApplied() throws {
        let session = try session(withLayerNamed: "Layer")
        // Adjustments the editor can't yet carry out fall through to the failure path rather than crashing.
        #expect(!session.applyAIIntent(EditingIntent(action: .adjustLevels)))
    }

    /// A mask image with `on` marking the selected (white) pixels, standing in for a segmentation map off the gateway.
    private func mask(width: Int, height: Int, on: (Int, Int) -> Bool) throws -> CGImage {
        let levels = (0 ..< width * height).map { on($0 % width, $0 / width) ? Float(1) : Float(0) }
        return try GuidedMatte.image(levels, width: width, height: height)
    }

    @Test func semanticMaskBecomesALayerMask() throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        let half = try mask(width: 200, height: 200) { x, _ in x < 100 }
        #expect(session.applySemanticMask(half))
        #expect(session.activeLayer?.mask != nil)
        // It's a normal edit, so it lands in history and undoes away again.
        session.undo()
        #expect(session.activeLayer?.mask == nil)
    }

    @Test func semanticSelectionBecomesMarchingAnts() throws {
        let session = try session(withLayerNamed: "Layer")
        let block = try mask(width: 200, height: 200) { x, y in x < 100 && y < 100 }
        #expect(session.applySemanticSelection(block))
        #expect(session.selection != nil)
        // An all-black mask encloses nothing, so there's no selection to make.
        let empty = try mask(width: 200, height: 200) { _, _ in false }
        #expect(!session.applySemanticSelection(empty))
    }

    @Test func semanticMaskNeedsASingleActiveLayer() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100) // No layers: nothing to mask.
        let blank = try mask(width: 100, height: 100) { _, _ in true }
        #expect(!session.applySemanticMask(blank))
    }
}
