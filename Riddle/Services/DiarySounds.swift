import AVFoundation

/// The diary's quiet voice of paper and ink — short bundled clips played very
/// softly. Uses the ambient audio session, so it mixes with the writer's music
/// and honours the silent switch, and every sound is gated by a setting.
@MainActor
final class DiarySounds {
    static let shared = DiarySounds()

    private var players: [String: AVAudioPlayer] = [:]
    private var enabled = true
    private var sessionReady = false

    func setEnabled(_ on: Bool) {
        enabled = on
        if !on { players.values.forEach { $0.stop() } }
    }

    /// Play a bundled clip once (or looping) at a soft volume.
    func play(_ name: String, volume: Float, loop: Bool = false) {
        guard enabled, let player = player(for: name) else { return }
        configureSession()
        player.volume = volume
        player.numberOfLoops = loop ? -1 : 0
        player.currentTime = 0
        player.play()
    }

    /// Fade a (usually looping) clip out gently.
    func stop(_ name: String, fade: TimeInterval = 0.3) {
        guard let player = players[name], player.isPlaying else { return }
        player.setVolume(0, fadeDuration: fade)
        let deadline = DispatchTime.now() + fade
        DispatchQueue.main.asyncAfter(deadline: deadline) {
            if player.volume == 0 { player.stop() }
        }
    }

    // MARK: - Internals

    private func player(for name: String) -> AVAudioPlayer? {
        if let existing = players[name] { return existing }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }

    private func configureSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
