import Foundation

/// The distilled soul of the writer — a compact profile the diary keeps across
/// every opening: names, recurring phrases, fears, wants, motifs, promises, open
/// threads. Small enough to travel in every first pass, so the diary always
/// *knows* the writer without a second round-trip.
@MainActor
final class MemorySoul: ObservableObject {
    @Published private(set) var facts: [String] = []

    private let fileURL: URL
    private let cap = 48

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("riddle-soul.json")
        load()
    }

    /// Merge freshly distilled facts (semicolon- or newline-separated) into the
    /// soul: dedupe, refresh recency, and cap. Most-recent first.
    func absorb(_ raw: String?) {
        guard let raw else { return }
        let incoming = raw
            .split(whereSeparator: { $0 == ";" || $0 == "\n" || $0 == "•" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var changed = false
        for fact in incoming {
            let clean = fact.count > 160 ? String(fact.prefix(160)) : fact
            let key = Self.normalized(clean)
            guard key.count > 2, !Self.isNothing(key) else { continue }

            if let index = facts.firstIndex(where: { Self.normalized($0) == key }) {
                if index != 0 {
                    facts.remove(at: index)
                    facts.insert(clean, at: 0)
                    changed = true
                }
            } else {
                facts.insert(clean, at: 0)
                changed = true
            }
        }

        if facts.count > cap {
            facts = Array(facts.prefix(cap))
            changed = true
        }
        if changed { save() }
    }

    /// The compact profile fed to the diary each turn (nil when it knows nothing).
    func profile() -> String? {
        guard !facts.isEmpty else { return nil }
        return facts.map { "• \($0)" }.joined(separator: "\n")
    }

    func forget() {
        facts = []
        save()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        facts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNothing(_ key: String) -> Bool {
        ["none", "nothing", "n/a", "no new facts", "no", "unknown"].contains(key)
    }
}
