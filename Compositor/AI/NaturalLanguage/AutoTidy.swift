import Foundation

/// One change the decision model proposes: a layer's new name, or a folder to wrap a set of layers in.
nonisolated struct TidySuggestion: Equatable, Identifiable {
    enum Kind: Equatable {
        case rename(layer: UUID, to: String)
        case group(name: String, layers: [UUID])
    }
    let id = UUID()
    let kind: Kind
    var label: String {
        switch kind {
        case .rename(let layer, let to): return "Rename \(layer.shortName) to “\(to)”"
        case .group(let name, let layers): return "Group \(layers.count) layers into “\(name)”"
        }
    }
}

private extension UUID {
    /// The first eight characters, enough to tell layers apart in a sentence without the noise of a full UUID.
    var shortName: String { uuidString.prefix(8).lowercased() }
}

/// Auto-Tidy: the decision model looks over the layer tree and proposes names and folders. It only reads
/// the tree — ids, names, depth — never the pixels, so the privacy mode that blocks pictures doesn't
/// need to block this. The suggestions come back as answers keyed by the questions asked; a loose shape
/// is accepted on purpose, since a small decision model wanders off-spec more than a chat model does.
nonisolated enum AutoTidy {
    /// The question the state travels with. English always: it's a prompt, not UI text.
    static let question = "These are the layers of an image project. Suggest better names for the ones "
        + "whose names mean nothing (Layer 1, back, dfh32), and groups of layers that belong together in a "
        + "folder. Answer with 'renames' (an array of {layerId, name}) and 'groups' (an array of "
        + "{name, layerIds}); use the ids exactly as given, and suggest nothing for a layer already well named."

    /// The layer rows written into the request: the tree the model is asked about.
    static func state(layers: [LayerHierarchy.Entry], width: Int, height: Int) -> [String: AnyCodable] {
        var tree: [[String: Any]] = []
        for row in layers {
            tree.append([
                "id": row.layer.id.uuidString,
                "name": row.layer.name,
                "depth": row.depth,
                "folder": row.layer.isGroup == true,
            ])
        }
        return [
            "document": AnyCodable(["width": width, "height": height]),
            "layers": AnyCodable(tree),
        ]
    }

    /// The suggestions an answer carries, in the order they should be applied: renames first, so a folder
    /// the model groups collects layers that already read well. Anything that doesn't name a real shape
    /// is dropped; a folder of one layer isn't a folder.
    static func suggestions(from response: SystemOneResponse, layers: [ImageLayer]) -> [TidySuggestion] {
        guard let answers = response.answers else { return [] }
        let names = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.name) })
        var result: [TidySuggestion] = []
        for rename in array(answers["renames"] ?? answers["rename"]) {
            guard let object = rename.value as? [String: Any],
                  let id = uuid(object["layerId"] ?? object["layer"] ?? object["id"]),
                  let raw = object["name"] ?? object["newName"],
                  let name = raw as? String, name.trimmingCharacters(in: .whitespacesAndNewlines).count > 2,
                  names[id] != nil, names[id] != name.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            result.append(TidySuggestion(kind: .rename(layer: id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))))
        }
        for group in array(answers["groups"] ?? answers["grouping"]) {
            guard let object = group.value as? [String: Any],
                  let raw = object["name"], let name = raw as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let ids = values(object["layerIds"] ?? object["layers"] ?? object["ids"]).compactMap { uuid($0.value) }
            let unique = Set(ids).filter { names[$0] != nil }
            guard unique.count >= 2 else { continue }
            // A stable order for the selection, whatever order the model listed them in.
            let ordered = layers.filter { unique.contains($0.id) }.map(\.id)
            result.append(TidySuggestion(kind: .group(name: name.trimmingCharacters(in: .whitespacesAndNewlines), layers: ordered)))
        }
        return result
    }

    /// A JSON value that should have been an array of objects; anything else is no list at all.
    private static func array(_ codable: AnyCodable?) -> [AnyCodable] { values(codable?.value) }

    /// The same, reading a raw decoded dictionary's value (already unwrapped from AnyCodable).
    private static func values(_ any: Any?) -> [AnyCodable] {
        (any as? [Any]).map { $0.map(AnyCodable.init) } ?? []
    }

    /// A layer id however the model wrote it: the string, or already a UUID.
    private static func uuid(_ value: Any?) -> UUID? {
        if let string = value as? String { return UUID(uuidString: string.trimmingCharacters(in: .whitespaces)) }
        return value as? UUID
    }

    /// Asks the decision model over the session's layer tree. The model's reasoning comes back with the
    /// suggestions, for the sheet to show beside the list.
    @MainActor static func suggest(over layers: [ImageLayer], width: Int, height: Int) async throws -> SystemOneResponse {
        let entries = LayerHierarchy.entries(layers.map(\.hierarchyRecord), topFirst: true)
        let request = SystemOneRequest(
            model: GatewayConfigurationStore.shared.model(for: .systemone) ?? "systemone",
            state: state(layers: entries, width: width, height: height),
            questions: [question]
        )
        return try await GatewayClient.shared.request(
            endpoint: .systemone, body: request, as: SystemOneResponse.self)
    }
}

extension EditorSession {
    /// Puts the accepted suggestions to the document, renames first, then folders. Every step rides the
    /// session's own undoable edits, so ⌘Z peels them off one at a time. Returns how many landed.
    @discardableResult
    func applyTidySuggestions(_ suggestions: [TidySuggestion]) -> Int {
        guard canEditLayers, !isProjectBusy, !isImporting else { return 0 }
        var applied = 0
        for suggestion in suggestions {
            switch suggestion.kind {
            case .rename(let layer, let to):
                guard document?.layers.contains(where: { $0.id == layer }) == true else { continue }
                renameLayer(layer, to: to)
                applied += 1
            case .group(let name, let layers):
                let live = layers.filter { id in document?.layers.contains(where: { $0.id == id }) == true }
                guard live.count >= 2 else { continue }
                selectLayers(Set(live), primary: live.first)
                groupSelectedLayers()
                // The new folder is what Group leaves active; give it the suggested name.
                if let group = activeLayer, group.isGroup { renameLayer(group.id, to: name) }
                applied += 1
            }
        }
        return applied
    }
}
