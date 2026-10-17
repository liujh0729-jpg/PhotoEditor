import Foundation

/// The one-request ballpark the AI sheets show before submitting, read off the catalog's pricing. A ballpark,
/// not a bill: the app never sees the gateway's usage accounting, and a catalog that doesn't say a price just
/// says so — the sheets then show "Cost unknown" rather than a made-up number.
nonisolated enum CostEstimate {
    /// Credits one request costs under these pricing terms, nil when the catalog doesn't say. `prompt` lets a
    /// token-priced slot scale its per-million figure down to this one submission; `resolution` picks the
    /// picture tier when the catalog splits prices by size.
    static func credits(for pricing: CatalogCapability.Pricing?, resolution: String? = nil,
                        prompt: String? = nil) -> Double? {
        guard let pricing else { return nil }
        if pricing.free == true { return 0 }
        guard pricing.enabled else { return nil }
        var raw: Double?
        if let resolution, let hit = pricing.byResolution?[resolution] {
            raw = hit
        } else if let tiers = pricing.imagePricing?.tiers, !tiers.isEmpty {
            raw = (resolution.flatMap { label in tiers.first { $0.resolution == label }?.price }) ?? tiers.first?.price
        }
        if raw == nil, let perMillion = pricing.promptPerMillion, let prompt {
            // Four characters to a token is the usual rough count; the estimate promises an order of magnitude.
            raw = perMillion * Double(max(prompt.count, 1)) / 4.0 / 1_000_000
        }
        guard let raw else { return nil }
        // The gateway coins its own units; the rate turns a price into the credits it bills.
        if let rate = pricing.awcoinRate, rate > 0 { return raw * rate }
        return raw
    }
}
