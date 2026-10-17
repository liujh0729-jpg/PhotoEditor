import CoreGraphics
import Foundation

/// One row of a retouch batch: the layer whose pixels go out and come back under the same preset.
struct RestoreBatchItem: Identifiable {
    let layerID: UUID
    let name: String
    let image: CGImage

    var id: UUID { layerID }
}

/// What a batch run leaves behind: the new pixels per layer, and the layers the gateway let down.
struct RestoreBatchOutcome {
    let retouched: [(layerID: UUID, image: CGImage)]
    let failed: [(name: String, message: String)]

    /// The names the panel lists when some layers didn't make it.
    var failureSummary: String { failed.map(\.name).joined(separator: ", ") }
}

/// The runner behind "Apply to all layers": one preset, every pixel layer, one layer at a time. Serial on
/// purpose — a canvas shouldn't fire N requests at the gateway at once, and a layer that fails is listed and
/// left in place while the rest keep going. `runner` is injected so the tests stub the network and pin the loop.
enum RestoreBatch {
    static func run(items: [RestoreBatchItem], preset: RestorePreset, model: String,
                    progress: (_ done: Int, _ total: Int) -> Void = { _, _ in },
                    runner: (RestoreBatchItem, RestorePreset, String) async throws -> CGImage) async -> RestoreBatchOutcome {
        var retouched: [(layerID: UUID, image: CGImage)] = []
        var failed: [(name: String, message: String)] = []
        for (index, item) in items.enumerated() {
            do {
                retouched.append((item.layerID, try await runner(item, preset, model)))
            } catch {
                failed.append((item.name, error.localizedDescription))
            }
            progress(index + 1, items.count)
        }
        return RestoreBatchOutcome(retouched: retouched, failed: failed)
    }
}
