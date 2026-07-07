import SwiftUI
import Combine
import CoreText

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
                let tilt = lineTilt + sin(seed * 12.9898) * 0.018
                let drift = lineDrift + sin(seed * 0.7) * 1.35 + sin(seed * 78.233) * 0.72
                var transform = CGAffineTransform(rotationAngle: tilt)
                    .concatenating(CGAffineTransform(translationX: gx, y: gy + drift))
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
    var color: Color
    var onComplete: () -> Void

    @State private var revealed: Double = 0
    @State private var completed = false
    @State private var layout = InkLayout(paths: [], frames: [], size: .zero)

    private let glyphsPerSecond: Double = 16
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var maxWidth: CGFloat {
        min(Theme.isPad ? 660 : 340, UIScreen.main.bounds.width - 72)
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
        layout = makeInkLayout(text: text, font: uiFont, maxWidth: maxWidth)
        revealed = 0
        completed = false
    }

    private func advance() {
        let target = Double(layout.glyphCount)
        if revealed < target {
            let rhythm = 0.72 + 0.5 * (0.5 + 0.5 * sin(revealed * 1.2))   // a hand's cadence
            revealed = min(target, revealed + (glyphsPerSecond * rhythm) / 60.0)
        }
        if !completed, streamFinished, target > 0, revealed >= target {
            completed = true
            onComplete()
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
                let wetness = max(0, 1.45 - recency) / 1.45
                if wetness > 0 {
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.13 * wetness)),
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
                with: .color(.white.opacity(0.28))
            )
        }
    }

    private func inkShade(for index: Int) -> Double {
        0.90 + 0.09 * Double((index * 47 + 19) % 97) / 96.0
    }
}
