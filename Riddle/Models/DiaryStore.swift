import Foundation

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
