import Foundation

/// One live back-and-forth in the open diary. This is intentionally not
/// persisted: it lasts while the app process is alive, then vanishes when the
/// diary is truly closed.
struct DiaryTurn: Hashable {
    var writer: String
    var reply: String
}

@MainActor
final class DiarySession: ObservableObject {
    private(set) var turns: [DiaryTurn] = []

    func add(writer: String, reply: String) {
        let writer = writer.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !writer.isEmpty || !reply.isEmpty else { return }
        turns.append(DiaryTurn(writer: writer.isEmpty ? "The writer's ink was difficult to read." : writer, reply: reply))
    }
}

/// Persists past exchanges to a JSON file in the app's Documents directory.
@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var entries: [DiaryEntry] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("riddle-entries.json")
        load()
    }

    func add(writer: String? = nil, reply: String, ink: Data?) {
        let writer = writer?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.insert(DiaryEntry(writer: writer?.isEmpty == false ? writer : nil, reply: reply, ink: ink), at: 0)
        save()
    }

    func delete(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func preservedMemoryContext(limit: Int = 12, excludingLiveTurns liveTurns: [DiaryTurn] = []) -> String? {
        let liveReplies = Set(liveTurns.map { Self.normalized($0.reply) })
        let lines = entries
            .filter { !liveReplies.contains(Self.normalized($0.reply)) }
            .prefix(limit)
            .enumerated()
            .compactMap { index, entry -> String? in
                let reply = Self.clipped(entry.reply, limit: 260)
                guard !reply.isEmpty else { return nil }

                if let writer = entry.writer, !writer.isEmpty {
                    return "\(index + 1). Writer: \"\(Self.clipped(writer, limit: 220))\" / Diary: \"\(reply)\""
                }
                return "\(index + 1). Diary answered: \"\(reply)\""
            }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// The diary's recall "tool": given what Tom wants to remember, return the
    /// most relevant kept pages (keyword-ranked, then filled with the most
    /// recent), formatted for the prompt. Nil when nothing has been kept.
    func recall(_ query: String, limit: Int = 6) -> String? {
        guard !entries.isEmpty else { return nil }

        let tokens = Self.tokens(query)
        let ranked = entries.enumerated()
            .map { index, entry -> (score: Int, recency: Int, entry: DiaryEntry) in
                let hay = Self.normalized((entry.writer ?? "") + " " + entry.reply)
                let score = tokens.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
                return (score, index, entry)
            }

        var chosen = ranked
            .filter { $0.score > 0 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.recency < $1.recency }
            .map { $0.entry }

        // Fill up with the most recent kept pages so a recall is never empty.
        if chosen.count < limit {
            for entry in entries where !chosen.contains(entry) {
                chosen.append(entry)
                if chosen.count >= limit { break }
            }
        }

        let lines = chosen.prefix(limit).enumerated().compactMap { index, entry -> String? in
            let reply = Self.clipped(entry.reply, limit: 260)
            guard !reply.isEmpty else { return nil }
            if let writer = entry.writer, !writer.isEmpty {
                return "\(index + 1). Writer: \"\(Self.clipped(writer, limit: 220))\" / Diary: \"\(reply)\""
            }
            return "\(index + 1). Diary answered: \"\(reply)\""
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "what", "that", "this", "with", "writer", "their",
        "them", "they", "about", "from", "have", "has", "you", "your", "name",
        "remember", "recall", "something", "anything", "when", "where", "who",
    ]

    private static func tokens(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([DiaryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func clipped(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
