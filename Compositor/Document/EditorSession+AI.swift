import Foundation
import CoreGraphics

/// The canvas side of the AI features: dropping a generated image as a layer, replacing the active
/// layer with an edited one, and running the natural-language intents that map onto existing edits.
/// Kept on the session so the sheets stay thin and the behavior is unit-testable without any UI.
extension EditorSession {
    /// Places a generated image on the canvas as a new layer, named after the source of the pixels.
    /// Returns false when the bitmap can't be read.
    @discardableResult
    func placeGeneratedImage(_ image: CGImage, named name: String) -> Bool {
        guard let thumbnail = try? PixelAdjust.thumbnail(of: image) else { return false }
        insert(ImportedImage(image: image, thumbnail: thumbnail, name: name))
        return true
    }

    /// Replaces the active (non-group) layer's pixels with an edited image, keeping its name and its place on the
    /// canvas, and resizing its transform to the new bitmap. A mask without its own placement is frozen to the
    /// old transform first so it doesn't stretch with the layer. The undo step folds into history like any pixel edit.
    /// Returns false when there's no eligible active layer or the image can't be read.
    @discardableResult
    func replaceActiveLayer(with image: CGImage) -> Bool {
        guard let document,
              let index = document.layers.firstIndex(where: { $0.id == activeLayerID }),
              document.layers[index].isGroup != true,
              let thumbnail = try? PixelAdjust.thumbnail(of: image) else { return false }
        let layer = document.layers[index]
        beginEdit("AI Edit")
        if layer.mask?.placement == nil { self.document?.layers[index].mask?.placement = layer.maskTransform }
        self.document?.layers[index].asset = ImportedImage(image: image, thumbnail: thumbnail, name: layer.name)
        self.document?.layers[index].transform.size = CGSize(width: image.width, height: image.height)
        endEdit()
        return true
    }

    /// Redraws a mask of any format (a segmentation map off the gateway is usually RGBA) into the monochrome,
    /// alpha-less 8-bit form a layer mask stores, at its own resolution. White reveals, black hides.
    private func normalizedMask(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let levels = try? GuidedMatte.levels(of: image, width: width, height: height),
              let gray = try? GuidedMatte.image(levels, width: width, height: height) else { return nil }
        return gray
    }

    /// Puts a semantic-selection mask on the active layer as a layer mask, white revealing — as if the mask had been
    /// painted in by hand. Returns false when there's no eligible active layer or the mask can't be read.
    @discardableResult
    func applySemanticMask(_ mask: CGImage) -> Bool {
        guard canEditMask, let document,
              let index = document.layers.firstIndex(where: { $0.id == activeLayerID }),
              document.layers[index].isGroup != true,
              let gray = normalizedMask(mask), let asset = try? LayerMask.asset(from: gray) else { return false }
        beginEdit("AI Mask")
        self.document?.layers[index].mask = LayerMask(asset: asset)
        endEdit()
        return true
    }

    /// Turns a semantic-selection mask into a live selection on the canvas: the mask's white area is traced along
    /// exact pixel edges and placed where the active layer sits, so it lines up with what the model saw.
    @discardableResult
    func applySemanticSelection(_ mask: CGImage) -> Bool {
        guard canEditSelection, let layer = activeLayer, layer.isGroup != true,
              let gray = normalizedMask(mask), let traced = MaskTracing.whitePixels(in: gray) else { return false }
        var toDocument = BrushRaster.pixelToDocument(layer.transform, width: gray.width, height: gray.height)
        guard let outline = traced.copy(using: &toDocument) else { return false }
        applySelection(outline, mode: .replace, name: "AI Selection")
        return selection != nil
    }

    /// Runs an editing intent against the canvas through the session's own edits, so it lands in history
    /// exactly like doing it by hand. Returns false for the intents the editor can't yet carry out, or
    /// those that don't apply to the current state (no active layer, no selection).
    @discardableResult
    func applyAIIntent(_ intent: EditingIntent) -> Bool {
        switch intent.action {
        case .deselect:
            deselect()
            return true
        case .invertSelection:
            guard selection != nil else { return false }
            invertSelection()
            return true
        case .deleteLayer:
            guard activeLayer != nil else { return false }
            deleteActiveLayer()
            return true
        case .duplicateLayer:
            guard let id = activeLayerID else { return false }
            return duplicateLayer(id, in: activeLayer?.parentID)
        case .renameLayer:
            guard let id = activeLayerID, let name = intent.parameters["name"]?.value as? String else { return false }
            renameLayer(id, to: name)
            return true
        case .addMask:
            guard activeLayer?.mask == nil, canEditMask else { return false }
            addLayerMask(revealing: true)
            return true
        default:
            return false
        }
    }
}
