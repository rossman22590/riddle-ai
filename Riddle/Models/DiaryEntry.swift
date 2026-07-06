import Foundation

/// A single page the diary answered: the ink the writer left (a small PNG) and
/// the reply that was written back.
struct DiaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var reply: String
    var ink: Data?
}
