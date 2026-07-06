import SwiftUI
import Combine

/// A `TextRenderer` that reveals glyphs one at a time, fading each in with a
/// small upward drift, and trails a soft glowing "nib" at the writing frontier —
/// so the diary's reply looks penned in real time.
struct HandwritingRenderer: TextRenderer, Animatable {
    /// Number of glyphs revealed so far (fractional for a smooth frontier).
    var revealed: Double
    var nibColor: Color
    var showNib: Bool

    var animatableData: Double {
        get { revealed }
        set { revealed = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        var frontier: CGRect?

        for line in layout {
            for run in line {
                for glyph in run {
                    // How recently this glyph was reached by the nib. <=0 means
                    // it hasn't been written yet; small positive = just inked.
                    let recency = revealed - Double(index)
                    if recency <= 0 { index += 1; continue }

                    // The stroke flows in as the nib passes over it.
                    let opacity = min(1, recency)
                    var copy = context
                    copy.opacity = opacity
                    copy.translateBy(x: 0, y: (1 - opacity) * 3)
                    copy.draw(glyph)

                    // Fresh ink stays wet — a soft dark bloom — then dries over
                    // the next couple of letters. This reads as inking, not fading.
                    if recency < 2 {
                        let wetness = (1 - recency / 2) * 0.6
                        var sheen = context
                        sheen.opacity = wetness * opacity
                        sheen.addFilter(.blur(radius: 1.2 + (1 - min(1, recency)) * 1.6))
                        sheen.translateBy(x: 0, y: (1 - opacity) * 3)
                        sheen.draw(glyph)
                        if recency < 1 { frontier = glyph.typographicBounds.rect }
                    }

                    index += 1
                }
            }
        }

        // The pen nib: a soft glow trailing the writing frontier.
        if showNib, let rect = frontier {
            let point = CGPoint(x: rect.maxX, y: rect.midY)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.fill(
                    Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                    with: .color(nibColor.opacity(0.5))
                )
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.5))
                layer.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .color(nibColor)
                )
            }
        }
    }
}

/// Static text drawn with the handwriting renderer at a given reveal amount.
struct HandwritingText: View {
    let text: String
    var revealed: Double
    var font: Font
    var color: Color
    var showNib: Bool

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineSpacing(Theme.isPad ? 16 : 10)
            .textRenderer(HandwritingRenderer(revealed: revealed, nibColor: Theme.accent, showNib: showNib))
    }
}

/// Drives the reveal forward at a steady cadence, independent of how fast the
/// network delivers text. Calls `onComplete` once, when the stream has finished
/// *and* the reveal has caught up.
struct RevealingHandwriting: View {
    let text: String
    var streamFinished: Bool
    var font: Font
    var color: Color
    var onComplete: () -> Void

    @State private var revealed: Double = 0
    @State private var completed = false

    private let glyphsPerSecond: Double = 19
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HandwritingText(
            text: text,
            revealed: revealed,
            font: font,
            color: color,
            showNib: revealed < Double(text.count)
        )
        .onReceive(tick) { _ in
            let target = Double(text.count)
            if revealed < target {
                // A hand's rhythm — the nib speeds and eases as it writes.
                let rhythm = 0.68 + 0.6 * (0.5 + 0.5 * sin(revealed * 1.25))
                revealed = min(target, revealed + (glyphsPerSecond * rhythm) / 60.0)
            }
            if !completed, streamFinished, target > 0, revealed >= target {
                completed = true
                onComplete()
            }
        }
    }
}

/// Renders faint cursive letters whose opacity travels in a slow wave, so the
/// letters fade in and out like ink stirring on the page.
struct ShimmerRenderer: TextRenderer {
    var phase: Double

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let wave = 0.5 + 0.5 * sin(phase * 1.7 - Double(index) * 0.55)
                    var copy = context
                    copy.opacity = 0.06 + 0.42 * wave
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

/// While the diary reads the page: faint letters in its own hand, fading in and
/// out like ink stirring — no indicator, just fades.
struct ThinkingIndicator: View {
    private let murmur = "the ink stirs"

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Text(murmur)
                .font(Theme.display(Theme.isPad ? 40 : 30))
                .foregroundStyle(Theme.replyInk)
                .textRenderer(ShimmerRenderer(phase: t))
        }
    }
}
