import Foundation

/// What the editor has learned from the intents that actually ran: for each action, the numeric parameters
/// it was given and how often. Purely local tallies in UserDefaults — nothing goes to the gateway, and a
/// fresh Mac starts with no preferences at all. The engine reads them when an intent arrives without a
/// number a panel would have typed; the sheet says so on the entry.
@MainActor
final class PreferenceStore {
    static let shared = PreferenceStore()

    private static let key = "aiParameterPreferences"
    /// action → parameter → value → times given. Read once at start; every write goes straight back to
    /// the defaults, and the read side reloads, so two stores in one process (a sheet and a test) can't
    /// step on each other's tallies.
    private var counts: [String: [String: [String: Int]]]

    private init() {
        counts = Self.load()
    }

    private static func load() -> [String: [String: [String: Int]]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: [String: Int]]].self, from: data) else { return [:] }
        return decoded
    }

    /// One more time `action` ran with `parameter` at `value`. Values are stored at three decimals:
    /// slider noise shouldn't split a tally in two, and a percent and a fraction are different habits.
    func record(action: String, parameter: String, value: Double) {
        guard value.isFinite else { return }
        counts = Self.load()
        let rounded = (value * 1000).rounded() / 1000
        counts[action, default: [:]][parameter, default: [:]][Self.name(rounded), default: 0] += 1
        save()
    }

    /// The value `action` was given under `parameter` most often, or nil while nothing has been recorded.
    func mostUsed(action: String, parameter: String) -> Double? {
        counts = Self.load()
        guard let byParameter = counts[action]?[parameter], let best = byParameter.max(by: { $0.value < $1.value })?.key else { return nil }
        return Double(best)
    }

    /// The numbers an intent carries, as the tallies keep them: model JSON lands as Int or Double
    /// depending on the value, and both names read the same number.
    static func parameters(of intent: EditingIntent) -> [(String, Double)] {
        var result: [(String, Double)] = []
        for (key, parameter) in intent.parameters {
            switch parameter.value {
            case let v as Double where v.isFinite: result.append((key, v))
            case let v as Int: result.append((key, Double(v)))
            default: break
            }
        }
        return result
    }

    /// Everything an intent that ran carried: one more tally per number, under its action.
    func record(_ intent: EditingIntent) {
        for (key, value) in Self.parameters(of: intent) {
            record(action: intent.action.rawValue, parameter: key, value: value)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// The tally's dictionary key for a value: plain enough that 50 and 50.0 share one row.
    private static func name(_ value: Double) -> String {
        formatted(value)
    }

    nonisolated static func formatted(_ value: Double) -> String {
        String(format: "%.3f", value).trimmingTrailingZeros
    }
}

private extension String {
    /// Drop the zeros that pad a fixed-width format to three decimals, so 0.80000 reads as 0.8 in the tally.
    var trimmingTrailingZeros: String {
        guard contains(".") else { return self }
        var text = Substring(self)
        while text.last == "0" { text = text.dropLast() }
        if text.last == "." { text = text.dropLast() }
        return String(text)
    }
}
