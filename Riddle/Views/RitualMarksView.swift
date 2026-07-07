import SwiftUI

/// Teaches the diary's marks the way the diary itself writes — each gesture is
/// drawn in ink, stroke by stroke, with a line in Tom's hand beneath it. Shown
/// once when the diary is first opened, and replayable from settings.
struct RitualMarksView: View {
    var onDone: () -> Void

    private enum Mark { case question, cross, zed, vee }

    private let marks: [(mark: Mark, caption: String)] = [
        (.question, "Draw a question mark,\nand my guide appears."),
        (.cross, "A great cross,\nand the page wipes clean."),
        (.zed, "A great Z,\nand I fall asleep."),
        (.vee, "A great V,\nand my memories open to you."),
    ]

    @State private var index = 0
    @State private var progress: CGFloat = 0
    @State private var captionShown = false
    @State private var advanceWork: DispatchWorkItem?

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: Theme.isPad ? 34 : 24) {
                Spacer()

                RitualStroke(path: markPath, progress: progress, color: Theme.replyInk)
                    .frame(width: Theme.isPad ? 260 : 188, height: Theme.isPad ? 260 : 188)

                Text(marks[index].caption)
                    .font(.custom("DancingScript-Regular", size: Theme.isPad ? 36 : 27))
                    .foregroundStyle(Theme.replyInk.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .opacity(captionShown ? 1 : 0)
                    .padding(.horizontal, 40)

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<marks.count, id: \.self) { i in
                        Circle()
                            .fill(Theme.ink.opacity(i == index ? 0.55 : 0.18))
                            .frame(width: 6, height: 6)
                    }
                }
                Text(index == marks.count - 1 ? "tap to begin" : "tap to continue")
                    .font(.custom("DancingScript-Regular", size: Theme.isPad ? 21 : 17))
                    .foregroundStyle(Theme.replyInk.opacity(0.4))
                    .padding(.top, 4)
                    .padding(.bottom, Theme.isPad ? 54 : 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear { play() }
        .onDisappear { advanceWork?.cancel() }
    }

    private var markPath: (CGRect) -> Path {
        let mark = marks[index].mark
        return { r in Self.path(for: mark, in: r) }
    }

    private func play() {
        progress = 0
        captionShown = false
        withAnimation(.easeInOut(duration: 1.3)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.6)) { captionShown = true }
        }
        let work = DispatchWorkItem { advance() }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.9, execute: work)   // auto-advance; a tap is faster
    }

    private func advance() {
        advanceWork?.cancel()
        if index < marks.count - 1 {
            index += 1
            play()
        } else {
            onDone()
        }
    }

    /// Each mark as the strokes a hand would actually draw, in a unit-ish box.
    private static func path(for mark: Mark, in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        var path = Path()
        switch mark {
        case .vee:
            path.move(to: p(0.20, 0.12)); path.addLine(to: p(0.50, 0.86)); path.addLine(to: p(0.80, 0.12))
        case .cross:
            path.move(to: p(0.16, 0.14)); path.addLine(to: p(0.84, 0.86))
            path.move(to: p(0.84, 0.14)); path.addLine(to: p(0.16, 0.86))
        case .zed:
            path.move(to: p(0.18, 0.18)); path.addLine(to: p(0.82, 0.18))
            path.addLine(to: p(0.18, 0.82)); path.addLine(to: p(0.82, 0.82))
        case .question:
            path.move(to: p(0.26, 0.30))
            path.addCurve(to: p(0.72, 0.31), control1: p(0.28, -0.02), control2: p(0.88, 0.02))
            path.addCurve(to: p(0.50, 0.58), control1: p(0.78, 0.44), control2: p(0.50, 0.42))
            path.addLine(to: p(0.50, 0.66))
            let dot = r.width * 0.045
            path.move(to: p(0.50, 0.84))
            path.addEllipse(in: CGRect(x: p(0.50, 0.84).x - dot, y: p(0.50, 0.84).y - dot, width: dot * 2, height: dot * 2))
        }
        return path
    }
}

/// Strokes a mark's path from start to `progress`, a wet nib riding the tip —
/// the same ink language as the diary's replies.
private struct RitualStroke: View {
    let path: (CGRect) -> Path
    var progress: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(x: size.width * 0.14, y: size.height * 0.1,
                           width: size.width * 0.72, height: size.height * 0.8)
            let full = path(r)
            let traced = full.trimmedPath(from: 0, to: max(0.0001, progress))
            let lineWidth = min(size.width, size.height) * (Theme.isPad ? 0.045 : 0.05)

            ctx.stroke(traced, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if progress < 1, let nib = traced.currentPoint {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.fill(Path(ellipseIn: CGRect(x: nib.x - 5, y: nib.y - 5, width: 10, height: 10)),
                               with: .color(color.opacity(0.9)))
                }
            }
        }
    }
}
