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

    @Test func renameIntentTargetsTheActiveLayer() async throws {
        let session = try session(withLayerNamed: "Before")
        let intent = EditingIntent(action: .renameLayer, parameters: ["name": AnyCodable("After")])
        #expect(await session.applyAIIntent(intent))
        #expect(session.activeLayer?.name == "After")
        // A rename with no name to give isn't an edit.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .renameLayer))))
    }

    @Test func duplicateAndDeleteIntentsChangeTheLayerStack() async throws {
        let session = try session(withLayerNamed: "Layer")
        #expect(await session.applyAIIntent(EditingIntent(action: .duplicateLayer)))
        #expect(session.document?.layers.count == 2)
        #expect(await session.applyAIIntent(EditingIntent(action: .deleteLayer)))
        #expect(session.document?.layers.count == 1)
    }

    @Test func addMaskIntentRunsOnceThenRefuses() async throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        #expect(await session.applyAIIntent(EditingIntent(action: .addMask)))
        #expect(session.activeLayer?.mask != nil)
        // The layer already has a mask, so the intent no longer applies.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .addMask))))
        // Removing it applies again; removing twice doesn't.
        #expect(await session.applyAIIntent(EditingIntent(action: .removeMask)))
        #expect(session.activeLayer?.mask == nil)
        #expect(!(await session.applyAIIntent(EditingIntent(action: .removeMask))))
    }

    @Test func invertMaskFlipsTheMaskPixels() async throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        session.addLayerMask(revealing: true)
        let before = try #require(session.activeLayer?.mask?.asset.image)
        #expect(await session.applyAIIntent(EditingIntent(action: .invertMask)))
        #expect(session.activeLayer?.mask?.asset.image !== before)
        // Without a mask there's nothing to invert.
        session.deleteLayerMask()
        #expect(!(await session.applyAIIntent(EditingIntent(action: .invertMask))))
    }

    @Test func selectionIntentsFollowTheCurrentSelection() async throws {
        let session = try session(withLayerNamed: "Layer")
        #expect(await session.applyAIIntent(EditingIntent(action: .deselect)))
        // There's nothing to invert without a selection.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .invertSelection))))
    }

    @Test func layerIntentsDoNothingWithoutAnActiveLayer() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100) // Empty: no layers yet.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .deleteLayer))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .duplicateLayer))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .renameLayer, parameters: ["name": AnyCodable("X")]))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .changeOpacity, parameters: ["opacity": AnyCodable(50)]))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .adjustLevels, parameters: ["black": AnyCodable(20)]))))
    }

    @Test func unknownIntentsAreReportedAsNotApplied() async throws {
        let session = try session(withLayerNamed: "Layer")
        // Adjustments the editor can't yet carry out fall through to the failure path rather than crashing.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .adjustLevels))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .strokeSelection))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .selectColorRange))))
    }

    @Test func adjustLevelsRewritesThePixels() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = try #require(session.activeLayer?.asset?.image)
        let intent = EditingIntent(action: .adjustLevels, parameters: ["black": AnyCodable(60), "white": AnyCodable(240)])
        #expect(await session.applyAIIntent(intent))
        // Committed like a panel OK: new pixels, one undo step away from the old ones.
        #expect(session.activeLayer?.asset?.image !== before)
        session.undo()
        #expect(session.activeLayer?.asset?.image === before)
    }

    @Test func adjustHueSaturationRewritesThePixels() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = try #require(session.activeLayer?.asset?.image)
        #expect(await session.applyAIIntent(EditingIntent(action: .adjustHueSaturation, parameters: ["saturation": AnyCodable(30)])))
        #expect(session.activeLayer?.asset?.image !== before)
        // Nothing asked for, nothing applied.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .adjustHueSaturation))))
    }

    @Test func filterIntentsCommitThroughThePanelPath() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = try #require(session.activeLayer?.asset?.image)
        let intent = EditingIntent(action: .adjustExposure, parameters: ["exposure": AnyCodable(0.5)])
        #expect(await session.applyAIIntent(intent))
        #expect(session.activeLayer?.asset?.image !== before)
        // Out-of-range numbers are refused rather than clamped behind the user's back.
        let bad = EditingIntent(action: .adjustExposure, parameters: ["exposure": AnyCodable(50)])
        #expect(!(await session.applyAIIntent(bad)))
    }

    @Test func curveIntentRebuildsTheRGBCurve() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = try #require(session.activeLayer?.asset?.image)
        // Decoded off the wire shape, the way a gateway response reaches the engine.
        let json = Data(#"{"action":"adjustCurves","parameters":{"points":[[64,96],[128,192],[192,208]]}}"#.utf8)
        let intent = try #require(try JSONDecoder().decode(EditingIntent.self, from: json))
        #expect(await session.applyAIIntent(intent))
        #expect(session.activeLayer?.asset?.image !== before)
    }

    @Test func blendModeAndOpacityIntentsLandOnTheActiveLayer() async throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        #expect(await session.applyAIIntent(EditingIntent(action: .changeBlendMode, parameters: ["mode": AnyCodable("Multiply")])))
        #expect(session.document?.layers.first(where: { $0.id == id })?.blendMode == .multiply)
        #expect(await session.applyAIIntent(EditingIntent(action: .changeOpacity, parameters: ["opacity": AnyCodable(50)])))
        #expect(session.document?.layers.first(where: { $0.id == id })?.opacity == 0.5)
        // A mode the editor doesn't know is not silently mapped to a near neighbor.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .changeBlendMode, parameters: ["mode": AnyCodable("Vivid Dye")]))))
    }

    @Test func groupingAndUngroupingIntentsRoundTrip() async throws {
        let session = try session(withLayerNamed: "Layer")
        #expect(await session.applyAIIntent(EditingIntent(action: .groupLayers)))
        #expect(session.activeLayer?.isGroup == true)
        #expect(await session.applyAIIntent(EditingIntent(action: .ungroupLayers)))
        #expect(session.activeLayer?.isGroup != true)
        #expect(session.document?.layers.count == 1)
    }

    @Test func reorderLayerIntentMovesTheActiveLayer() async throws {
        let session = try session(withLayerNamed: "Bottom")
        session.placeGeneratedImage(try solidImage(width: 40, height: 40), named: "Top")
        let id = try #require(session.activeLayerID)
        // Already the frontmost layer: "up" has nowhere to go.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .reorderLayers, parameters: ["to": AnyCodable("up")]))))
        #expect(await session.applyAIIntent(EditingIntent(action: .reorderLayers, parameters: ["to": AnyCodable("back")])))
        #expect(session.document?.layers.first?.id == id)
    }

    @Test func flipAndTransformIntentsMoveTheLayer() async throws {
        let session = try session(withLayerNamed: "Layer")
        let transform = try #require(session.activeLayer?.transform)
        #expect(await session.applyAIIntent(EditingIntent(action: .transformLayer, parameters: ["dx": AnyCodable(20)])))
        #expect(session.activeLayer?.transform != transform)
        let moved = try #require(session.activeLayer?.transform)
        #expect(await session.applyAIIntent(EditingIntent(action: .flipLayer, parameters: ["axis": AnyCodable("horizontal")])))
        #expect(session.activeLayer?.transform.flipX == !moved.flipX)
        // Nothing asked to change: nothing applied.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .transformLayer))))
    }

    @Test func cropIntentResizesTheCanvas() async throws {
        let session = try session(withLayerNamed: "Layer", width: 200, height: 200)
        let crop = EditingIntent(action: .cropCanvas, parameters: ["x": AnyCodable(10), "y": AnyCodable(20), "width": AnyCodable(100), "height": AnyCodable(80)])
        #expect(await session.applyAIIntent(crop))
        #expect(session.document?.size == CGSize(width: 100, height: 80))
        // A crop box reaching past the canvas is refused.
        let bad = EditingIntent(action: .cropCanvas, parameters: ["x": AnyCodable(150), "width": AnyCodable(100), "height": AnyCodable(100)])
        #expect(!(await session.applyAIIntent(bad)))
    }

    @Test func adjustmentLayerIntentAddsOneNamedKind() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = session.document?.layers.count ?? 0
        #expect(await session.applyAIIntent(EditingIntent(action: .addAdjustmentLayer, parameters: ["kind": AnyCodable("curves")])))
        #expect(session.document?.layers.count == before + 1)
        #expect(session.activeLayer?.adjustment?.kind == .curves)
        // And the follow-up intent takes it back off again.
        #expect(await session.applyAIIntent(EditingIntent(action: .removeAdjustmentLayer)))
        #expect(session.document?.layers.count == before)
    }

    @Test func applyFilterIntentRunsANamedFilter() async throws {
        let session = try session(withLayerNamed: "Layer")
        let before = try #require(session.activeLayer?.asset?.image)
        let intent = EditingIntent(action: .applyFilter, parameters: ["name": AnyCodable("Gaussian Blur"), "radius": AnyCodable(8)])
        #expect(await session.applyAIIntent(intent))
        #expect(session.activeLayer?.asset?.image !== before)
        // A filter that isn't a plain one-click filter isn't run blind.
        #expect(!(await session.applyAIIntent(EditingIntent(action: .applyFilter, parameters: ["name": AnyCodable("Remove Background")]))))
        #expect(!(await session.applyAIIntent(EditingIntent(action: .applyFilter, parameters: ["name": AnyCodable("Imaginarium")]))))
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

    /// The threshold steps Vision's soft edge hard: what comes out is black or white, one clean break, and
    /// a higher threshold keeps less of the ramp.
    @Test func subjectMaskCutStepsGraysToBlackAndWhite() throws {
        let width = 101, height = 4
        let ramp = (0 ..< width * height).map { Float($0 % width) / Float(width - 1) }
        let picture = try GuidedMatte.image(ramp, width: width, height: height)
        func cut(_ threshold: Double) throws -> [Float] {
            try GuidedMatte.levels(of: try SemanticSelection.cut(picture, threshold: threshold), width: width, height: height)
        }
        let low = try cut(0.2), high = try cut(0.8)
        #expect((low + high).allSatisfy { $0 == 0 || $0 == 1 }, "a cut leaves no grays")
        #expect(low.filter { $0 == 1 }.count > high.filter { $0 == 1 }.count, "a higher threshold keeps less of the ramp")
        for levels in [low, high] {
            for y in 0 ..< height {
                let row = Array(levels[(y * width) ..< ((y + 1) * width)])
                let back = zip(row, row.dropFirst()).filter { $0 == 1 && $1 == 0 }.count
                #expect(back == 0, "one clean step across the row, y \(y)")
            }
        }
    }

    /// The subject pass over a simple scene: it hands back a hard mask at the picture's size with the blob in it —
    /// or says there's no subject, which a synthetic picture can honestly be.
    @Test func subjectMaskRunsVisionOnAScene() async throws {
        let width = 200, height = 200
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 60, y: 60, width: 80, height: 80))
        let picture = try #require(context.makeImage())
        do {
            let mask = try await Task.detached(priority: .userInitiated) {
                try SemanticSelection.subjectMask(in: picture, threshold: 0.5)
            }.value
            #expect(mask.width == width && mask.height == height)
            let levels = try GuidedMatte.levels(of: mask, width: width, height: height)
            #expect(levels.allSatisfy { $0 == 0 || $0 == 1 }, "the model's edge is cut hard")
            #expect(levels[width * (height / 2) + width / 2] == 1, "the blob is the subject")
            #expect(levels.first == 0, "the corner is background")
        } catch SemanticSelection.Failure.noSubject {
            // Vision may find no subject in a synthetic scene; that's the honest error, not a placeholder.
        }
    }

    /// The prompt is the name the edit takes: History reads "the cat", not a generic label.
    @Test func promptNamesTheSemanticEdit() throws {
        let session = try session(withLayerNamed: "Layer")
        let id = try #require(session.activeLayerID)
        session.selectedLayerIDs = [id]
        let half = try mask(width: 200, height: 200) { x, _ in x < 100 }
        #expect(session.applySemanticMask(half, name: "the cat"))
        #expect(session.history.undoName == "the cat")
        #expect(session.applySemanticSelection(half, name: "the sky"))
        #expect(session.history.undoName == "the sky")
        // With no prompt to borrow, the edits keep their own names.
        #expect(session.applySemanticMask(half))
        #expect(session.history.undoName == "AI Mask")
    }
}
