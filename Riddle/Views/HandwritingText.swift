import SwiftUI
import Combine
import CoreText
import UIKit

/// The diary's hand, laid out as real glyph outlines (via Core Text) so the
/// reply can be *drawn* — each letter's contour traced by a moving nib — rather
/// than faded in. Computed once per reply, then animated cheaply.
struct InkLayout {
    var paths: [Path]      // per-glyph outlines, already in canvas (y-down) space
    var frames: [CGRect]   // per-glyph bounds (for spacing / fallback)
    var size: CGSize
    var glyphCount: Int { paths.count }
}

func makeInkLayout(text: String, font: UIFont, maxWidth: CGFloat) -> InkLayout {
    let trimmed = text
    guard !trimmed.isEmpty else { return InkLayout(paths: [], frames: [], size: .zero) }

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineSpacing = font.pointSize * 0.30

    let attributed = NSAttributedString(string: trimmed, attributes: [.font: font, .paragraphStyle: para])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)

    var fitRange = CFRange()
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: 0),
        nil,
        CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        &fitRange
    )
    let size = CGSize(width: ceil(suggested.width) + 6,
                      height: ceil(suggested.height) + font.pointSize * 0.5)

    let framePath = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, nil)
    let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
    var origins = [CGPoint](repeating: .zero, count: lines.count)
    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

    let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
    // Core Text is y-up; flip into the SwiftUI canvas (y-down) space.
    let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)

    var paths: [Path] = []
    var frames: [CGRect] = []

    for (lineIndex, line) in lines.enumerated() {
        let lineOrigin = lineIndex < origins.count ? origins[lineIndex] : .zero
        let lineSeed = Double(lineIndex + 1)
        let lineDrift = sin(lineSeed * 2.17) * 1.2
        let lineTilt = sin(lineSeed * 3.11) * 0.005
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            if count == 0 { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

            for glyphIndex in 0..<count {
                let gx = lineOrigin.x + positions[glyphIndex].x
                let gy = lineOrigin.y + positions[glyphIndex].y

                // A living hand, not a typeset font: each letter drifts off the
                // baseline and tilts a hair — a smooth wave plus fine jitter,
                // seeded by position so it's stable, never a wall of clones.
                let seed = Double(paths.count)
                let tilt = lineTilt + sin(seed * 12.9898) * 0.021
                let drift = lineDrift + sin(seed * 0.7) * 1.45 + sin(seed * 78.233) * 0.86
                let sideDrift = sin(seed * 37.719) * 0.48
                let stretchX = 1 + sin(seed * 5.313) * 0.007
                let stretchY = 1 + sin(seed * 9.710) * 0.005
                var transform = CGAffineTransform(scaleX: stretchX, y: stretchY)
                    .concatenating(CGAffineTransform(rotationAngle: tilt))
                    .concatenating(CGAffineTransform(translationX: gx + sideDrift, y: gy + drift))
                    .concatenating(flip)

                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[glyphIndex], nil),
                   let moved = glyphPath.copy(using: &transform) {
                    let path = Path(moved)
                    paths.append(path)
                    frames.append(path.boundingRect)
                } else {
                    // Spaces have no outline; keep the slot so pacing stays even.
                    paths.append(Path())
                    frames.append(CGRect(x: gx, y: size.height - gy - 2, width: 4, height: 4))
                }
            }
        }
    }

    return InkLayout(paths: paths, frames: frames, size: size)
}

/// Draws the reply one letter at a time: the body inks in behind a nib that
/// traces each glyph's outline, so it reads as a hand writing in real ink.
struct RevealingHandwriting: View {
    let text: String
    var streamFinished: Bool
    var uiFont: UIFont
    var maxWidth: CGFloat? = nil
    var color: Color
    var haptics: Bool = false
    var onComplete: () -> Void

    @State private var revealed: Double = 0
    @State private var completed = false
    @State private var layout = InkLayout(paths: [], frames: [], size: .zero)
    @State private var characters: [Character] = []
    @State private var lastHapticGlyph = 0
    private let hapticGen = UIImpactFeedbackGenerator(style: .light)

    private let glyphsPerSecond: Double = 12.2
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var layoutMaxWidth: CGFloat {
        maxWidth ?? min(Theme.isPad ? 660 : 340, UIScreen.main.bounds.width - 72)
    }

    var body: some View {
        Canvas { context, size in
            draw(into: &context, size: size)
        }
        .frame(width: max(1, layout.size.width), height: max(1, layout.size.height))
        .onAppear(perform: rebuild)
        .onChange(of: text) { rebuild() }
        .onReceive(tick) { _ in advance() }
    }

    private func rebuild() {
        layout = makeInkLayout(text: text, font: uiFont, maxWidth: layoutMaxWidth)
        characters = Array(text)
        revealed = 0
        completed = false
        lastHapticGlyph = 0
    }

    private func advance() {
        let target = Double(layout.glyphCount)
        if revealed < target {
            let rhythm = 0.62 + 0.42 * (0.5 + 0.5 * sin(revealed * 1.2))   // a hand's cadence
            let unevenness = 0.82 + 0.24 * (0.5 + 0.5 * sin(revealed * 2.73))
            let hesitation = hesitationMultiplier(at: Int(revealed))
            revealed = min(target, revealed + (glyphsPerSecond * rhythm * unevenness * hesitation) / 60.0)

            // A whisper of texture as the nib moves — the pen felt, not just seen.
            if haptics {
                let glyph = Int(revealed)
                if glyph > lastHapticGlyph {
                    lastHapticGlyph = glyph
                    if glyph % 3 == 0 { hapticGen.impactOccurred(intensity: 0.28) }
                }
            }
        }
        if !completed, streamFinished, target > 0, revealed >= target {
            completed = true
            onComplete()
        }
    }

    private func hesitationMultiplier(at index: Int) -> Double {
        guard index >= 0, index < characters.count else { return 1 }
        switch characters[index] {
        case ".", "!", "?":
            return 0.28
        case ",", ";", ":":
            return 0.48
        case "\n":
            return 0.38
        case " ":
            return 1.35
        default:
            return 1
        }
    }

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        let lineWidth = max(1.1, uiFont.pointSize * 0.026)
        var nib: CGPoint?

        for (index, path) in layout.paths.enumerated() {
            if path.isEmpty { continue }
            let recency = revealed - Double(index)
            if recency <= 0 { continue }

            let shade = inkShade(for: index)
            let ink = GraphicsContext.Shading.color(color.opacity(shade))

            if recency >= 1 {
                context.fill(path, with: ink)          // written and dry

                // For a breath after the nib leaves, the stroke is still wet and
                // darker along its edge. Subtle enough to feel like pressure.
                let wetness = max(0, 1.7 - recency) / 1.7
                if wetness > 0 {
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.15 * wetness)),
                        style: StrokeStyle(lineWidth: lineWidth * 2.2, lineCap: .round, lineJoin: .round)
                    )
                }
            } else {
                let frac = recency
                // The body inks in behind the moving nib…
                context.fill(path, with: .color(color.opacity(shade * frac * frac)))
                // …while the nib traces the letter's outline in real time.
                let traced = path.trimmedPath(from: 0, to: frac)
                context.stroke(
                    traced,
                    with: ink,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                nib = traced.currentPoint ?? nib
            }
        }

        // The pen's tip: a small pool of wet ink riding the point being inked —
        // dark and glistening, not a bright cursor. A faint sheen sits atop it.
        if let nib {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.6))
                layer.fill(
                    Path(ellipseIn: CGRect(x: nib.x - 3.6, y: nib.y - 3.6, width: 7.2, height: 7.2)),
                    with: .color(color.opacity(0.92))
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: nib.x - 3.0, y: nib.y - 3.6, width: 2.1, height: 2.1)),
                with: .color(Theme.paper.opacity(0.38))
            )
        }
    }

    private func inkShade(for index: Int) -> Double {
        0.90 + 0.09 * Double((index * 47 + 19) % 97) / 96.0
    }
}
