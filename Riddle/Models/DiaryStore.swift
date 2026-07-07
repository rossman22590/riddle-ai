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

    func add(reply: String, ink: Data?) {
        entries.insert(DiaryEntry(reply: reply, ink: ink), at: 0)
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
}
