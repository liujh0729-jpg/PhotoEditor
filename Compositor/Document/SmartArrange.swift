import CoreGraphics
import Foundation

/// Smart Arrange: line the layers in play up by their actual content — the opaque pixels, or a worn mask's
/// white — along a canvas edge, or space that content evenly. The math is pure and works on content boxes in
/// document pixels, so a run is one history entry and every case is checkable without a canvas.
nonisolated enum SmartArrange {
    /// One layer's place and content for the arranging math: its transform, and where its content sits inside
    /// that box in unit terms (x and y from 0 to 1 across the layer's own frame).
    struct Row {
        let id: UUID
        let transform: LayerTransform
        let content: CGRect
    }

    /// How far each layer's transform slides under `command`, keyed by layer id. An edge alignment pulls the
    /// content to that canvas edge and leaves the other axis alone; Align Centers squares both. Rotated or
    /// flipped layers take their frame as their box — a content rect would no longer mean the same place —
    /// and the distribution spaces the first layer's run to keep its gaps, moving only along its axis.
    static func shifts(for command: SmartArrangeCommand, rows: [Row], canvas: CGSize) -> [UUID: CGSize] {
        guard !rows.isEmpty else { return [:] }
        let boxes = rows.map { row in
            let t = row.transform
            guard t.rotation == 0, !t.flipX, !t.flipY else { return CGRect(origin: t.origin, size: t.size) }
            return CGRect(x: t.origin.x + row.content.minX * t.size.width,
                          y: t.origin.y + row.content.minY * t.size.height,
                          width: row.content.width * t.size.width,
                          height: row.content.height * t.size.height)
        }
        let canvasBox = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        var moves: [(x: CGFloat, y: CGFloat)] = Array(repeating: (0, 0), count: rows.count)
        switch command {
        case .alignLeft:
            for (i, box) in boxes.enumerated() { moves[i].x = canvasBox.minX - box.minX }
        case .alignCenters:
            for (i, box) in boxes.enumerated() {
                moves[i].x = canvasBox.midX - box.midX
                moves[i].y = canvasBox.midY - box.midY
            }
        case .alignRight:
            for (i, box) in boxes.enumerated() { moves[i].x = canvasBox.maxX - box.maxX }
        case .alignTop:
            for (i, box) in boxes.enumerated() { moves[i].y = canvasBox.minY - box.minY }
        case .alignBottom:
            for (i, box) in boxes.enumerated() { moves[i].y = canvasBox.maxY - box.maxY }
        case .distributeHorizontally, .distributeVertically:
            let horizontal = command == .distributeHorizontally
            let edge = { (box: CGRect) in horizontal ? box.minX : box.minY }
            let far = { (box: CGRect) in horizontal ? box.maxX : box.maxY }
            let span = { (box: CGRect) in horizontal ? box.width : box.height }
            let sorted = boxes.indices.sorted { edge(boxes[$0]) < edge(boxes[$1]) }
            // What sat between the neighbours to begin with, on average; negative where they overlap.
            var gaps: [CGFloat] = []
            for step in 1..<sorted.count {
                gaps.append(edge(boxes[sorted[step]]) - far(boxes[sorted[step - 1]]))
            }
            let mean = gaps.isEmpty ? CGFloat(0) : gaps.reduce(0, +) / CGFloat(gaps.count)
            var cursor = edge(boxes[sorted[0]])
            for i in sorted {
                let move = cursor - edge(boxes[i])
                if horizontal { moves[i].x = move } else { moves[i].y = move }
                cursor += span(boxes[i]) + mean
            }
        }
        var result: [UUID: CGSize] = [:]
        for (i, row) in rows.enumerated() {
            let offset = CGSize(width: moves[i].x.rounded(), height: moves[i].y.rounded())
            if offset != .zero { result[row.id] = offset }
        }
        return result
    }
}

/// The commands the Layer menu lists, in order.
nonisolated enum SmartArrangeCommand: String, CaseIterable {
    case alignLeft = "Align Left"
    case alignCenters = "Align Centers"
    case alignRight = "Align Right"
    case alignTop = "Align Top"
    case alignBottom = "Align Bottom"
    case distributeHorizontally = "Distribute Horizontally"
    case distributeVertically = "Distribute Vertically"
}

extension EditorSession {
    /// Whether the menu offers a run: at least two selected pixel layers to line up.
    var canSmartArrange: Bool {
        guard canEditLayers, let document else { return false }
        let ids = selectedLayerIDs.isEmpty ? Set(activeLayerID.map { [$0] } ?? []) : selectedLayerIDs
        return document.layers.filter { ids.contains($0.id) && $0.isGroup != true && $0.asset != nil }.count >= 2
            && !smartArrangeInFlight
    }

    /// Runs a Smart Arrange command over the layers in play — `ids`, or the selected ones (the active layer
    /// counts as a selection of one) — as a single history entry. The command needs a set: fewer than two
    /// content-carrying pixel layers, and nothing moves. Returns how many layers did.
    @discardableResult
    func applySmartArrange(_ command: SmartArrangeCommand, layerIDs: Set<UUID>? = nil) async -> Int {
        // Refuse a second run while one is mid-flight: the pixel scan suspends the main actor for a beat, and
        // a re-entrant run would compute its moves from a layout the first run hasn't applied yet.
        guard !smartArrangeInFlight else { return 0 }
        guard canEditLayers, let document else { return 0 }
        smartArrangeInFlight = true
        defer { smartArrangeInFlight = false }
        let ids = layerIDs ?? (selectedLayerIDs.isEmpty ? Set(activeLayerID.map { [$0] } ?? []) : selectedLayerIDs)
        let live = document.layers.filter { ids.contains($0.id) && $0.isGroup != true && $0.adjustment == nil }
        // Snapshot the pixels and transforms here, then scan each layer's opaque bounds off the main actor:
        // a full-resolution RGBA buffer per layer is enough to freeze the menu for seconds on a big canvas,
        // and the scan is pure (nothing main-actor-isolated), so it runs cleanly detached.
        let inputs = live.compactMap { layer -> (id: UUID, transform: LayerTransform, image: CGImage, mask: CGImage?)? in
            guard let image = layer.asset?.image else { return nil }
            let mask = layer.mask.flatMap { $0.isEnabled ? $0.asset.image : nil }
            return (layer.id, layer.transform, image, mask)
        }
        let canvas = document.size
        let rows: [SmartArrange.Row] = await Task.detached(priority: .userInitiated) {
            inputs.map {
                SmartArrange.Row(id: $0.id, transform: $0.transform,
                                 content: EditorSession.contentBounds(of: $0.image, mask: $0.mask))
            }
        }.value
        guard rows.count >= 2 else { return 0 }
        let moves = SmartArrange.shifts(for: command, rows: rows, canvas: canvas)
        guard !moves.isEmpty else { return 0 }
        beginEdit("Smart Arrange")
        var moved = 0
        for (id, offset) in moves {
            guard let index = self.document?.layers.firstIndex(where: { $0.id == id }) else { continue }
            var transform = self.document!.layers[index].transform
            transform.origin.x += offset.width
            transform.origin.y += offset.height
            guard transform.isValid else { continue }
            self.document!.layers[index].transform = transform
            moved += 1
        }
        endEdit()
        return moved
    }

    /// Where a layer's picture actually is inside its box, in unit terms: the smallest rect around the opaque
    /// pixels, or around a mask's white when the layer wears an enabled one. An empty reading gives the whole
    /// box, so such a layer at least aligns with itself.
    nonisolated static func contentBounds(of image: CGImage, mask: CGImage?) -> CGRect {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let bytesPerRow = width * 4
        var storage = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(data: &storage, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var opaque = (0..<(width * height)).map { storage[$0 * 4 + 3] > 0 }
        if let mask, mask.width > 0, mask.height > 0 {
            // The mask read at the picture's size: white reveals, so the content is what's painted
            // *and* uncovered.
            let maskPerRow = mask.width * 4
            var maskStorage = [UInt8](repeating: 0, count: maskPerRow * mask.height)
            if let maskContext = CGContext(data: &maskStorage, width: mask.width, height: mask.height, bitsPerComponent: 8,
                                           bytesPerRow: maskPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                maskContext.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
                for y in 0..<height {
                    // Nearest-neighbour onto the picture's grid; half gray and up reveals.
                    let my = min(mask.height - 1, y * mask.height / height)
                    for x in 0..<width {
                        let mx = min(mask.width - 1, x * mask.width / width)
                        opaque[y * width + x] = opaque[y * width + x] && maskStorage[my * maskPerRow + mx * 4] >= 128
                    }
                }
            }
        }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where opaque[y * width + x] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
