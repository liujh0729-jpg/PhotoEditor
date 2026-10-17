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
    /// painted in by hand. `name` is what the history entry reads, the prompt the user typed. Returns false when
    /// there's no eligible active layer or the mask can't be read.
    @discardableResult
    func applySemanticMask(_ mask: CGImage, name: String? = nil) -> Bool {
        guard canEditMask, let document,
              let index = document.layers.firstIndex(where: { $0.id == activeLayerID }),
              document.layers[index].isGroup != true,
              let gray = normalizedMask(mask), let asset = try? LayerMask.asset(from: gray) else { return false }
        beginEdit(name ?? "AI Mask")
        self.document?.layers[index].mask = LayerMask(asset: asset)
        endEdit()
        return true
    }

    /// Turns a semantic-selection mask into a live selection on the canvas: the mask's white area is traced along
    /// exact pixel edges and placed where the active layer sits, so it lines up with what the model saw.
    @discardableResult
    func applySemanticSelection(_ mask: CGImage, name: String? = nil) -> Bool {
        guard canEditSelection, let layer = activeLayer, layer.isGroup != true,
              let gray = normalizedMask(mask), let traced = MaskTracing.whitePixels(in: gray) else { return false }
        var toDocument = BrushRaster.pixelToDocument(layer.transform, width: gray.width, height: gray.height)
        guard let outline = traced.copy(using: &toDocument) else { return false }
        applySelection(outline, mode: .replace, name: name ?? "AI Selection")
        return selection != nil
    }

    /// Puts text off the OCR sheet onto the canvas as a new live-text layer, through the Type tool's own path:
    /// it lands in history exactly like it had been typed. Returns false when the canvas can't take an edit.
    @discardableResult
    func insertRecognizedText(_ text: String) -> Bool {
        guard let document, textDraft == nil else { return false }
        beginText(at: CGPoint(x: document.size.width / 2, y: document.size.height / 2), newLayer: true)
        guard var draft = textDraft else { return false }
        draft.style.content = text
        return applyText(draft)
    }

    /// Auto Crop: Vision's saliency picks the composition and the canvas becomes the suggested box, through the
    /// same resizer the Crop tool commits with — so it lands in history like a hand-drawn crop. The reading is
    /// local work, so it keeps working in Privacy Mode.
    func autoCrop() async {
        guard let document, canStartProjectOperation,
              let sample = selectionSample(document, sampleAllLayers: true) else { return }
        guard let rect = await SmartCrop.suggestRect(in: sample) else {
            cropError = "No clear subject was found to crop to. Try a picture with a distinct subject."
            return
        }
        await applyAutoCrop(rect: rect)
    }

    /// Crops the canvas to Auto Crop's suggested box. A box that is the whole canvas says "leave it as it is".
    func applyAutoCrop(rect: CGRect) async {
        guard let document else { return }
        let width = Int(rect.width.rounded()), height = Int(rect.height.rounded())
        guard width > 0, height > 0, width < document.width || height < document.height else { return }
        _ = await resizeCanvas(toWidth: width, height: height,
                               offset: CGPoint(x: -rect.minX.rounded(), y: -rect.minY.rounded()),
                               actionName: "Auto Crop")
    }

    /// Runs an editing intent against the canvas through the session's own edits, so it lands in history
    /// exactly like doing it by hand. Returns false for the intents the editor can't carry out — the ones
    /// it has no feature for (a selection border stroke, sampling a color range by hand), or those that
    /// don't apply to the current state (no active layer, no selection, nothing to change).
    @discardableResult
    func applyAIIntent(_ intent: EditingIntent) async -> Bool {
        switch intent.action {
        // Structural edits that need no parameters.
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
            guard let id = activeLayerID, let name = intent.text("name") else { return false }
            renameLayer(id, to: name)
            return true
        case .addMask:
            guard activeLayer?.mask == nil, canEditMask else { return false }
            addLayerMask(revealing: true)
            return true
        case .removeMask:
            guard activeLayer?.mask != nil, canEditMask else { return false }
            deleteLayerMask()
            return activeLayer?.mask == nil
        case .invertMask:
            guard let document, let index = document.layers.firstIndex(where: { $0.id == activeLayerID }),
                  let before = document.layers[index].mask?.asset.image else { return false }
            // Invert runs against whatever the panel targets, so the mask is selected for the duration.
            isMaskSelected = true
            await invertPixels()
            isMaskSelected = false
            return self.document?.layers[index].mask?.asset.image !== before
        case .removeAdjustmentLayer:
            guard activeLayer?.adjustment != nil else { return false }
            deleteActiveLayer()
            return true
        case .addAdjustmentLayer:
            guard canEditLayers, let document else { return false }
            let raw = intent.text("kind") ?? intent.text("type") ?? "Levels"
            // Loose on purpose: "curves", "Curves" and "Color Balance" all name an adjustment kind.
            let kind = AdjustmentKind.allCases.first { $0.rawValue.lowercased() == raw.lowercased() }
                ?? AdjustmentKind.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == raw.lowercased().replacingOccurrences(of: " ", with: "") }
                ?? .levels
            let before = document.layers.count
            addAdjustment(kind)
            // Adding through the menu also opens that kind's settings panel; an intent just wants the layer,
            // so the panel state is dropped again — nothing was edited, so there is nothing to commit.
            adjustmentEditingID = nil
            return (self.document?.layers.count ?? 0) > before

        // Color intents, run through the same begin/commit path the panels use. Success is read
        // from the pixels: a commit that failed or changed nothing leaves the old image in place.
        case .adjustLevels:
            guard let settings = levelsSettings(for: intent) else { return false }
            focusActiveLayer()
            guard canAdjustColors, let document,
                  let index = document.layers.firstIndex(where: { $0.id == activeLayerID }) else { return false }
            let before = document.layers[index].asset?.image
            beginLevels()
            guard levels != nil else { return false }
            updateLevels(settings, preview: false)
            await commitLevels()
            return self.document?.layers[index].asset?.image !== before
        case .adjustHueSaturation:
            let hue = intent.number("hue") ?? 0
            let saturation = intent.number("saturation") ?? intent.number("sat") ?? 0
            let lightness = intent.number("lightness") ?? intent.number("brightness") ?? 0
            guard hue != 0 || saturation != 0 || lightness != 0 else { return false }
            focusActiveLayer()
            guard canAdjustColors, let document,
                  let index = document.layers.firstIndex(where: { $0.id == activeLayerID }) else { return false }
            let before = document.layers[index].asset?.image
            beginHueSaturation()
            guard hueSaturation != nil else { return false }
            updateHueSaturation(HueSaturationSettings(hue: hue, saturation: saturation, lightness: lightness), preview: false)
            await commitHueSaturation()
            return self.document?.layers[index].asset?.image !== before
        case .adjustExposure:
            return await runFilter(.exposure) { settings in
                var value = settings.exposure
                var touched = false
                if let v = intent.number("exposure") { value.exposure = v; touched = true }
                if let v = intent.number("offset") { value.offset = v; touched = true }
                if let v = intent.number("gamma") { value.gamma = v; touched = true }
                guard touched, value.isValid, value != ExposureSettings() else { return false }
                settings.exposure = value
                return true
            }
        case .adjustColorBalance:
            return await runFilter(.colorBalance) { settings in
                var value = settings.colorBalance
                var touched = false
                let paths: [(String, WritableKeyPath<ColorBalanceSettings, Double>)] = [
                    ("shadowCyanRed", \.shadowCyanRed), ("shadowMagentaGreen", \.shadowMagentaGreen), ("shadowYellowBlue", \.shadowYellowBlue),
                    ("midCyanRed", \.midCyanRed), ("midMagentaGreen", \.midMagentaGreen), ("midYellowBlue", \.midYellowBlue),
                    ("highlightCyanRed", \.highlightCyanRed), ("highlightMagentaGreen", \.highlightMagentaGreen), ("highlightYellowBlue", \.highlightYellowBlue),
                ]
                for (key, path) in paths {
                    if let v = intent.number(key) { value[keyPath: path] = v; touched = true }
                }
                // Conversational shorthand: warmth pushes the mid tones toward red/yellow, a cool
                // request pulls them the other way; tint rides the magenta/green axis.
                if let warmth = intent.number("warmth") ?? intent.number("temperature") {
                    value.midCyanRed += warmth
                    value.midYellowBlue += warmth
                    touched = true
                }
                if let tint = intent.number("tint") {
                    value.midMagentaGreen += tint
                    touched = true
                }
                guard touched, value.isValid else { return false }
                settings.colorBalance = value
                return true
            }
        case .adjustCurves:
            return await runFilter(.curves) { settings in
                let interior = curvePoints(intent.parameters["points"]?.value).filter { $0.x > 0 && $0.x < 255 && $0.y >= 0 && $0.y <= 255 }
                guard !interior.isEmpty else { return false }
                var value = settings.curves
                value.channels[LevelsChannel.rgb.index] =
                    [CurvePoint(x: 0, y: 0)] + interior.sorted { $0.x < $1.x } + [CurvePoint(x: 255, y: 255)]
                guard value.isValid else { return false }
                settings.curves = value
                return true
            }

        // Layer appearance and stack. Most of these edits guard on the panel's selection rules,
        // so the engine pins the active layer as the sole selection first, as a click on it would.
        case .changeBlendMode:
            guard let raw = intent.text("mode") ?? intent.text("blendMode"),
                  let mode = LayerBlendMode.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() })
            else { return false }
            focusActiveLayer()
            guard canEditAppearance, let id = activeLayerID else { return false }
            setLayerBlendMode(mode)
            return document?.layers.first(where: { $0.id == id })?.blendMode == mode
        case .changeOpacity:
            guard var value = intent.number("opacity") ?? intent.number("value") else { return false }
            if value > 1 { value /= 100 } // Models speak in percents as often as fractions.
            focusActiveLayer()
            guard (0...1).contains(value), canEditOpacity, let id = activeLayerID else { return false }
            setLayerOpacity(value)
            return document?.layers.first(where: { $0.id == id })?.opacity == value
        case .groupLayers:
            guard canEditLayers, activeLayer != nil else { return false }
            if selectedLayerIDs.isEmpty, let id = activeLayerID { selectedLayerIDs = [id] }
            let before = document?.layers.count ?? 0
            groupSelectedLayers()
            return (document?.layers.count ?? 0) > before
        case .ungroupLayers:
            guard canEditLayers else { return false }
            let before = document?.layers.count ?? 0
            ungroupLayers()
            return (document?.layers.count ?? 0) < before
        case .reorderLayers:
            guard canEditLayers, let id = activeLayerID, let document,
                  let docIndex = document.layers.firstIndex(where: { $0.id == id }) else { return false }
            let place = (intent.text("to") ?? intent.text("direction") ?? "up").lowercased()
            switch place {
            case "up": guard canMoveActiveLayer(by: 1) else { return false }; moveActiveLayer(by: 1)
            case "down": guard canMoveActiveLayer(by: -1) else { return false }; moveActiveLayer(by: -1)
            case "front": reorderLayers(from: IndexSet(integer: document.layers.count - 1 - docIndex), to: 0)
            case "back": reorderLayers(from: IndexSet(integer: document.layers.count - 1 - docIndex), to: document.layers.count)
            default: return false
            }
            return self.document?.layers.firstIndex(where: { $0.id == id }) != docIndex
        case .transformLayer:
            guard canEditLayers, let document, let index = document.layers.firstIndex(where: { $0.id == activeLayerID }),
                  document.layers[index].isGroup != true else { return false }
            let dx = intent.number("dx") ?? 0
            let dy = intent.number("dy") ?? 0
            let scale = intent.number("scale")
            let turn = intent.number("rotation") ?? intent.number("angle")
            guard dx != 0 || dy != 0 || scale != nil || turn != nil else { return false }
            var moved = document.layers[index].transform
            if let scale, scale > 0, scale != 1 {
                let center = moved.center
                moved.size = CGSize(width: moved.size.width * CGFloat(scale), height: moved.size.height * CGFloat(scale))
                moved.origin = CGPoint(x: center.x - moved.size.width / 2, y: center.y - moved.size.height / 2)
            }
            if let turn { moved.rotation += CGFloat(turn) }
            moved.origin.x += CGFloat(dx)
            moved.origin.y += CGFloat(dy)
            guard moved.isValid else { return false }
            beginEdit("AI Transform")
            self.document?.layers[index].transform = moved
            endEdit()
            return true
        case .flipLayer:
            guard canEditLayers, activeLayer?.isGroup != true else { return false }
            focusActiveLayer()
            let was = document?.layers.map(\.transform)
            flipLayers(horizontally: (intent.text("axis") ?? "horizontal") != "vertical")
            return document?.layers.map(\.transform) != was

        // Canvas. Crop and resize go through CanvasResizer, the same path Trim and the Crop tool commit on.
        case .rotateCanvas:
            guard canEditLayers, let before = document?.size else { return false }
            let clockwise = (intent.text("direction") ?? "clockwise") != "counterclockwise"
            rotateCanvas(clockwise: clockwise)
            return document?.size != before
        case .flipCanvas:
            guard canEditLayers, let before = document?.layers.map(\.transform) else { return false }
            flipCanvas(horizontally: (intent.text("axis") ?? "horizontal") != "vertical")
            return document?.layers.map(\.transform) != before
        case .cropCanvas:
            guard let document else { return false }
            let x = intent.number("x") ?? intent.number("left") ?? 0
            let y = intent.number("y") ?? intent.number("top") ?? 0
            guard let width = intent.whole("width"), let height = intent.whole("height"),
                  width > 0, height > 0,
                  CGFloat(width) <= document.size.width - CGFloat(x), CGFloat(height) <= document.size.height - CGFloat(y),
                  x >= 0, y >= 0 else { return false }
            return await resizeCanvas(toWidth: width, height: height, offset: CGPoint(x: -x, y: -y), actionName: "AI Crop")
        case .resizeCanvas:
            guard let width = intent.whole("width"), let height = intent.whole("height"), width > 0, height > 0 else { return false }
            return await resizeCanvas(toWidth: width, height: height, offset: nil, actionName: "AI Canvas Size")

        // Selection tools.
        case .selectSubject:
            guard canEditSelection, activeLayer?.asset != nil else { return false }
            await selectSubject(mode: .replace)
            return selection != nil
        case .expandSelection, .contractSelection, .featherSelection:
            guard selection != nil else { return false }
            let amount = intent.whole("amount") ?? (intent.action == .featherSelection ? 5 : 1)
            guard amount > 0, amount <= 4096 else { return false }
            switch intent.action {
            case .expandSelection: expandSelection(by: amount)
            case .contractSelection: contractSelection(by: amount)
            case .featherSelection: featherSelection(by: amount)
            default: return false
            }
            return true
        case .fillSelection:
            guard canEditPixels, activeLayer?.asset != nil else { return false }
            let named = (intent.text("source") ?? intent.text("with"))?.lowercased()
            await fillSelection(with: named == "background" ? .background : .foreground)
            return true
        case .applyFilter:
            guard let raw = intent.text("name") ?? intent.text("filter"),
                  let kind = FilterKind.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }),
                  !kind.isAutomatic else { return false }
            return await runFilter(kind) { settings in
                // The one parameter every filter family answers to in casual requests.
                if kind == .gaussianBlur, let radius = intent.number("radius"), (0.1...250).contains(radius) {
                    settings.radius = radius
                }
                return true
            }
        // Honest refusals, for now: a border stroke around a selection isn't a feature this editor has,
        // and Select Color Range samples from an interactive pick, neither of which an intent can drive yet.
        default:
            return false
        }
    }

    /// Pins the active layer as the sole panel selection, so edits guarded by selection rules —
    /// blend mode, opacity, masks — answer to the intent the way they do to a click.
    private func focusActiveLayer() {
        guard let id = activeLayerID else { return }
        if selectedLayerIDs != [id] { selectedLayerIDs = [id] }
    }

    /// Opens a Filter-menu edit, lets the intent write its numbers into the settings, and commits —
    /// the panel's own path without the panel. A false from `apply` (nothing to change, values out
    /// of range) cancels the edit as pressing Cancel would. Success reads from the layer's pixels,
    /// so a commit that changed nothing or failed counts as not applied.
    private func runFilter(_ kind: FilterKind, apply: (inout FilterSettings) -> Bool) async -> Bool {
        focusActiveLayer()
        guard canAdjustColors else { return false }
        beginFilter(kind)
        guard let edit = filterEdit else { return false }
        var settings = edit.settings
        guard apply(&settings) else { cancelFilter(); return false }
        edit.settings = settings
        guard let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }),
              let before = document?.layers[index].asset?.image else { cancelFilter(); return false }
        await commitFilter()
        return self.document?.layers[index].asset?.image !== before
    }

    /// Resizes or crops the canvas through the project's own resizer, applied like Trim does.
    private func resizeCanvas(toWidth width: Int, height: Int, offset: CGPoint?, actionName: String) async -> Bool {
        guard canStartProjectOperation, let snapshot = projectSnapshot() else { return false }
        isProjectBusy = true
        defer { isProjectBusy = false }
        guard let resized = try? await CanvasResizer.shared.resize(
            snapshot, to: CanvasSizeOptions(width: width, height: height, contentOffset: offset)) else { return false }
        applyDocumentSize(resized, actionName: actionName)
        return true
    }

    /// Levels from an intent's numbers, in the editor's native 0–255; values given as 0–1 fractions
    /// (a model often does) are scaled up. Nil when the intent carries nothing to set.
    private func levelsSettings(for intent: EditingIntent) -> LevelsSettings? {
        var range = LevelRange()
        var touched = false
        func fractionOrRaw(_ key: String) -> Double? {
            guard let v = intent.number(key) else { return nil }
            return v <= 1 && v >= 0 ? v * 255 : v
        }
        if let v = intent.number("black") { range.black = v; touched = true }
        else if let v = fractionOrRaw("shadows") { range.black = v; touched = true }
        if let v = intent.number("white") { range.white = v; touched = true }
        else if let v = fractionOrRaw("highlights") { range.white = v; touched = true }
        if let v = intent.number("gamma") { range.gamma = v; touched = true }
        if let v = intent.number("outputBlack") { range.outputBlack = v; touched = true }
        if let v = intent.number("outputWhite") { range.outputWhite = v; touched = true }
        guard touched else { return nil }
        var settings = LevelsSettings()
        settings.current = range
        return settings.isIdentity ? nil : settings
    }

    /// Curve control points from the wire shape: an array of [x, y] pairs in 0–255.
    private func curvePoints(_ raw: Any?) -> [CurvePoint] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let pair = row as? [Any], pair.count >= 2,
                  let x = numberValue(pair[0]), let y = numberValue(pair[1]) else { return nil }
            return CurvePoint(x: x, y: y)
        }
    }

    private func numberValue(_ raw: Any) -> Double? {
        if let v = raw as? Double { return v.isFinite ? v : nil }
        if let v = raw as? Int { return Double(v) }
        return nil
    }
}

/// Intent parameter readers. A model sending JSON numbers lands as `Int` or `Double` depending on
/// the value, so every read tries both; text the model might send as a number is not chased.
fileprivate extension EditingIntent {
    func number(_ key: String) -> Double? {
        switch parameters[key]?.value {
        case let v as Double: return v.isFinite ? v : nil
        case let v as Int: return Double(v)
        default: return nil
        }
    }
    func whole(_ key: String) -> Int? {
        switch parameters[key]?.value {
        case let v as Int: return v
        case let v as Double: return v.isFinite ? Int(v) : nil
        default: return nil
        }
    }
    func text(_ key: String) -> String? { parameters[key]?.value as? String }
}
