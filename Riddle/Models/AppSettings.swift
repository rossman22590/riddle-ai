import SwiftUI

/// App-wide, persisted settings. The OpenRouter API key lives in the Keychain;
/// everything else lives in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) } }
    @Published var hasSeenMarks: Bool  { didSet { defaults.set(hasSeenMarks, forKey: Keys.seenMarks) } }
    @Published var model: String       { didSet { defaults.set(model, forKey: Keys.model) } }
    @Published var replyHand: String   { didSet { defaults.set(replyHand, forKey: Keys.hand) } }
    @Published var pauseDelay: Double   { didSet { defaults.set(pauseDelay, forKey: Keys.pause) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    @Published var soundEnabled: Bool   { didSet { defaults.set(soundEnabled, forKey: Keys.sound) } }
    @Published var drawingEnabled: Bool { didSet { defaults.set(drawingEnabled, forKey: Keys.drawing) } }
    @Published var imageModel: String   { didSet { defaults.set(imageModel, forKey: Keys.imageModel) } }

    /// Mirrors whether a key is stored, so views can react without touching the Keychain.
    @Published private(set) var apiKeyIsSet: Bool = false

    // Claude Haiku 4.5 — fast, smart, and vision-capable (reads the ink well).
    static let defaultModel = "anthropic/claude-haiku-4.5"
    // The ink-illustration model (only used for drawings, always ink-styled).
    static let defaultImageModel = "google/gemini-3.1-flash-lite-image"

    private enum Keys {
        static let onboarded = "hasOnboarded"
        static let seenMarks = "hasSeenMarks"
        static let model = "model"
        static let hand = "replyHand"
        static let pause = "pauseDelay"
        static let haptics = "hapticsEnabled"
        static let sound = "soundEnabled"
        static let drawing = "drawingEnabled"
        static let imageModel = "imageModel"
        static let migratedModel = "migratedModelToHaiku"
        static let apiKey = "openrouter.apiKey"
    }

    init() {
        hasOnboarded   = defaults.bool(forKey: Keys.onboarded)
        hasSeenMarks   = defaults.bool(forKey: Keys.seenMarks)
        let storedModel = defaults.string(forKey: Keys.model)
        model          = storedModel ?? Self.defaultModel
        replyHand      = defaults.string(forKey: Keys.hand) ?? "Dancing Script"
        pauseDelay     = defaults.object(forKey: Keys.pause) as? Double ?? 2.8
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        soundEnabled   = defaults.object(forKey: Keys.sound) as? Bool ?? true
        drawingEnabled = defaults.object(forKey: Keys.drawing) as? Bool ?? true
        imageModel     = defaults.string(forKey: Keys.imageModel) ?? Self.defaultImageModel
        apiKeyIsSet    = !(Keychain.load(key: Keys.apiKey) ?? "").isEmpty

        // One-time move off the old default to Claude Haiku 4.5 for a better
        // experience. (didSet doesn't fire during init, so persist manually.)
        if !defaults.bool(forKey: Keys.migratedModel) {
            if storedModel == "openai/gpt-4o-mini" {
                model = Self.defaultModel
                defaults.set(model, forKey: Keys.model)
            }
            defaults.set(true, forKey: Keys.migratedModel)
        }
    }

    var apiKey: String { Keychain.load(key: Keys.apiKey) ?? "" }

    func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(key: Keys.apiKey)
        } else {
            Keychain.save(key: Keys.apiKey, value: trimmed)
        }
        apiKeyIsSet = !trimmed.isEmpty
    }
}
