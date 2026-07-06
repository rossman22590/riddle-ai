import SwiftUI

/// A deterministic pseudo-random generator so the paper grain stays stable
/// across redraws (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The e-ink page: a flat, matte paper-white surface with the faintest grain and
/// a barely-there edge — the look of a reMarkable page, not glossy parchment.
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.paper

            Canvas { ctx, size in
                var rng = SeededRNG(seed: 0x5EED)
                for _ in 0..<360 {
                    let x = Double.random(in: 0...size.width, using: &rng)
                    let y = Double.random(in: 0...size.height, using: &rng)
                    let s = Double.random(in: 0.4...1.4, using: &rng)
                    let a = Double.random(in: 0.01...0.045, using: &rng)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                        with: .color(Theme.ink.opacity(a))
                    )
                }
            }
            .blendMode(.multiply)

            // A whisper of edge shading so the page reads as physical paper.
            RadialGradient(
                colors: [.clear, Theme.paperEdge.opacity(0.5)],
                center: .center,
                startRadius: 420,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}
