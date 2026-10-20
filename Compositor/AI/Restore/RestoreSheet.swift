import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// The AI Retouch & Enhance panel: a table of preset instructions (remove watermark, de-noise, upscale…) run
/// against the active layer through the gateway. The request pipeline is the Image Editing sheet's: the picture
/// and a mask, when one applies, go multipart to the preset's capability slot; the answer lands on a layer
/// through the session's own edits, so it folds into history like any other change.
struct RestoreSheet: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String? = RestorePresets.all[0].id
    @State private var model: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var result: CGImage?
    @State private var allLayers = false
    @State private var batchDone = 0
    @State private var batchTotal = 0

    private var preset: RestorePreset { RestorePresets.all.first { $0.id == selectedID } ?? RestorePresets.all[0] }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Retouch & Enhance…")
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

            HStack(spacing: 0) {
                // Left: the preset table and the model override.
                VStack(alignment: .leading, spacing: 0) {
                    List(RestorePresets.all, selection: $selectedID) { item in
                        Label(item.title, systemImage: item.symbol)
                    }
                    .listStyle(.sidebar)
                    .accessibilityIdentifier("retouchPresets")

                    HStack {
                        Text("Model")
                            .font(.caption)
                        TextField("Slot default", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    .padding(8)

                    Toggle("Apply to all layers", isOn: $allLayers)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .disabled(isProcessing || preset.subjectCompositing)
                        .help(preset.subjectCompositing
                              ? "The subject cutout runs on one layer at a time."
                              : "Run this preset on every pixel layer, one after another.")
                }
                .frame(width: 280)

                Divider()

                // Right: source and result, one step apart.
                VStack(spacing: 12) {
                    if let source = session.activeLayer?.asset?.image {
                        HStack(spacing: 12) {
                            previewTile(source, caption: "Source")
                            if let result {
                                previewTile(result, caption: "Retouched")
                            } else if isProcessing {
                                VStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Retouching…").font(.caption).foregroundColor(.secondary)
                                    if allLayers {
                                        // The batch counts its way through the stack; the numbers need no catalog.
                                        Text("\(batchDone)/\(batchTotal)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 180, height: 180)
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 34))
                                        .foregroundColor(.secondary)
                                    Text("No result yet").font(.caption).foregroundColor(.secondary)
                                }
                                .frame(width: 180, height: 180)
                            }
                        }
                    } else {
                        Text("No pixel layer to retouch. Select a layer first.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }

            Divider()

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The picture goes to the gateway model the slot names. A selection or an enabled mask limits what gets touched.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // The ballpark the catalog's pricing gives for one request of this preset's slot.
                    Text(CatalogStore.shared.estimate(for: preset.endpointSlot, prompt: preset.prompt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 260, alignment: .leading)

                Spacer()

                Button("Apply") { run() }
                    .disabled(session.activeLayer?.asset == nil || isProcessing)

                Button("Replace Layer") { land(replacing: true) }
                    .disabled(result == nil)

                Button("Add as New Layer") { land(replacing: false) }
                    .disabled(result == nil)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 720, height: 540)
        .background(Color(white: 0.14))
    }

    private func previewTile(_ image: CGImage, caption: String) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: NSImage(cgImage: image, size: .zero))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
                .cornerRadius(6)
            Text(caption).font(.caption).foregroundColor(.secondary)
        }
    }

    /// Runs the preset against the layer's pixels. The request is the Image Editing sheet's pipeline: image,
    /// mask when one applies, the preset's prompt, and the slot's model unless the field overrides it.
    /// With "Apply to all layers" on, the same preset walks every pixel layer one at a time instead, and the
    /// whole run lands as a single history entry; a layer the gateway lets down is listed and keeps its pixels.
    /// The subject cutout works on one layer at a time, so it never enters the batch.
    private func run() {
        guard let source = session.activeLayer?.asset?.image else { return }
        isProcessing = true
        errorMessage = nil
        result = nil
        if allLayers && !preset.subjectCompositing {
            let items = batchItems()
            guard !items.isEmpty else { isProcessing = false; return }
            batchDone = 0
            batchTotal = items.count
            let preset = self.preset
            let model = resolvedModel(preset)
            Task {
                let outcome = await RestoreBatch.run(items: items, preset: preset, model: model,
                                                     progress: { done, _ in batchDone = done })
                { item, preset, model in
                    let parts = Self.multipartParts(image: item.image, mask: nil, preset: preset, model: model)
                    let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                        endpoint: preset.endpointSlot, parts: parts, as: ImageResponse.self)
                    return try await Self.firstImage(of: response)
                }
                isProcessing = false
                let changed = session.applyRestoreBatch(outcome.retouched, actionName: preset.title)
                if !outcome.failed.isEmpty {
                    errorMessage = String(format: NSLocalizedString("Couldn't retouch: %@.", comment: ""),
                                          outcome.failureSummary)
                }
                if changed > 0 { dismiss() }
            }
            return
        }
        let preset = self.preset
        Task {
            do {
                // The background generation paints behind Vision's subject cutout: the mask that ships
                // points at everything but the subject, and the answer comes back under the subject.
                let back = preset.subjectCompositing
                    ? try await Self.invert(Self.subjectMask(of: source))
                    : editMask()
                let parts = Self.multipartParts(image: source, mask: back, preset: preset,
                                                model: resolvedModel(preset))
                let response: ImageResponse = try await GatewayClient.shared.uploadMultipart(
                    endpoint: preset.endpointSlot, parts: parts, as: ImageResponse.self)
                let edited = try await Self.firstImage(of: response)
                result = preset.subjectCompositing ? try Self.composite(subject: source, over: edited, back: back) : edited
                isProcessing = false
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Vision's foreground subjects, cut out on this Mac; nothing but the mask's pixels leaves the sheet.
    static func subjectMask(of image: CGImage) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try SemanticSelection.subjectMask(in: image, threshold: 0.5)
        }.value
    }

    /// White where the subject isn't, black where it is: the mask the generator repaints.
    static func invert(_ mask: CGImage) throws -> CGImage {
        // CoreImage's own negative: no blend-mode guesswork about what a bitmap context does to a gray image.
        let inverted = CIImage(cgImage: mask).applyingFilter("CIColorInvert")
        // createCGImage returns nil when the render fails (memory pressure, an empty-extent mask). Throw the
        // same way composite() does below rather than force-unwrapping and crashing the sheet on a bad mask.
        guard let out = CIContext().createCGImage(inverted, from: CGRect(x: 0, y: 0, width: mask.width, height: mask.height)) else {
            throw GatewayClientError.invalidResponse
        }
        return out
    }

    /// The subject from `source`, laid back over the generated `background`: white in `back` (the area the
    /// model was asked to paint) lets the answer through, the subject's own pixels stay on top.
    static func composite(subject source: CGImage, over background: CGImage, back: CGImage?) throws -> CGImage {
        guard let back else { return source }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let context = CIContext()
        // CIBlendWithMask: the image where the mask is white, the background it's black.
        func masked(_ image: CGImage, _ mask: CGImage) -> CIFilter? {
            guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
            filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
            filter.setValue(CIImage(cgImage: mask), forKey: kCIInputMaskImageKey)
            filter.setValue(CIImage(cgImage: background), forKey: kCIInputBackgroundImageKey)
            return filter
        }
        // Where the cutout's white says "paint here", keep the answer; where it's black, keep the subject.
        guard let kept = masked(background, back)?.outputImage,
              let subject = masked(source, try invert(back))?.outputImage,
              let out = context.createCGImage(subject.composited(over: kept), from: bounds) else {
            throw GatewayClientError.invalidResponse
        }
        return out
    }

    private func resolvedModel(_ preset: RestorePreset) -> String {
        model.isEmpty ? (GatewayConfigurationStore.shared.model(for: preset.endpointSlot) ?? "gpt-image-1") : model
    }

    /// Every layer the batch can take: a pixel layer, not a group.
    private func batchItems() -> [RestoreBatchItem] {
        guard let document = session.document else { return [] }
        return document.layers.compactMap { layer in
            guard layer.isGroup != true, let image = layer.asset?.image else { return nil }
            return RestoreBatchItem(layerID: layer.id, name: layer.name, image: image)
        }
    }

    /// What limits the edit: the background generation's Vision cutout when the preset composites, else a
    /// live selection (white is the area to touch), else the layer's own enabled mask; none, the whole picture goes.
    private func editMask() -> CGImage? {
        if let selection = session.selection, let layer = session.activeLayer, let canvas = session.document?.size,
           layer.asset != nil {
            let width = layer.asset?.image.width ?? Int(layer.size.width.rounded())
            let height = layer.asset?.image.height ?? Int(layer.size.height.rounded())
            guard width > 0, height > 0,
                  let context = try? BrushRaster.context(width: width, height: height, mask: true),
                  let clip = try? selection.clip(canvas: canvas) else { return nil }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.concatenate(BrushRaster.pixelToDocument(layer.transform, width: width, height: height).inverted())
            clip.apply(to: context)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(clip.rect)
            return context.makeImage()
        }
        return session.activeLayer?.mask.flatMap { $0.isEnabled ? $0.asset.image : nil }
    }

    /// Builds the form fields; the tests pin the wire format without a network.
    static func multipartParts(image: CGImage, mask: CGImage?, preset: RestorePreset,
                               model: String) -> [MultipartPart] {
        var parts: [MultipartPart] = []
        if let sourcePart = ImageBridge.multipartPart(for: image, name: "image") {
            parts.append(sourcePart)
        }
        if let mask, let maskPart = ImageBridge.multipartPart(for: mask, name: "mask") {
            parts.append(maskPart)
        }
        parts.append(.text("prompt", preset.prompt))
        parts.append(.text("model", model))
        parts.append(.text("n", "1"))
        parts.append(.text("response_format", "b64_json"))
        return parts
    }

    /// The first image the response carries, decoded or downloaded, the way the Image Editing sheet reads it.
    static func firstImage(of response: ImageResponse) async throws -> CGImage {
        for imageData in response.data {
            if let b64 = imageData.b64_json, let image = ImageBridge.cgImage(fromBase64: b64) { return image }
            if let urlStr = imageData.url, let url = URL(string: urlStr) {
                return try await ImageBridge.downloadImage(from: url)
            }
        }
        throw GatewayClientError.invalidResponse
    }

    /// The result lands through the session's own edits, so history reads like any layer change.
    private func land(replacing: Bool) {
        guard let result else { return }
        let done = replacing ? session.replaceActiveLayer(with: result)
                             : session.placeGeneratedImage(result, named: preset.title)
        if done { dismiss() } else { errorMessage = "Couldn't apply to the active layer. Select a pixel layer first." }
    }
}
