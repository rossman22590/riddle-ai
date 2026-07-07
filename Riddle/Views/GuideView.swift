import SwiftUI

/// The built-in guide — summoned by drawing a "?" or a two-finger tap. Rendered
/// as a page of the diary, not an iOS panel. Every mark is drawn in ink.
struct GuideView: View {
    var onSettings: () -> Void
    var onHistory: () -> Void

    private enum Mark { case pen, cross, question, vee, zed }

    var body: some View {
        DiarySheet(title: "Riddle") {
            VStack(alignment: .leading, spacing: 26) {
                DiaryText("Write to me, and rest your pen. I will read your hand and answer in mine.",
                          size: 17, opacity: 0.7)

                VStack(alignment: .leading, spacing: 20) {
                    row(.pen, "Write, then rest your pen",
                        "The diary drinks your ink and answers in its own hand.")
                    row(.cross, "Draw a large  X",
                        "Wipes the page without opening any controls.")
                    row(.question, "Draw a  ?  on the page",
                        "Summons this guide, at any time.")
                    row(.vee, "Draw a large  V",
                        "Opens the diary's memory.")
                    row(.zed, "Draw a large  Z",
                        "Lets the diary sleep.")
                }

                VStack(spacing: 12) {
                    inkButton("The ink & the voice", action: onSettings)
                    inkButton("The diary's memory", action: onHistory)
                }
                .padding(.top, 8)
            }
        }
    }

    private func row(_ mark: Mark, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Canvas { ctx, s in
                let r = CGRect(x: s.width * 0.1, y: s.height * 0.1, width: s.width * 0.8, height: s.height * 0.8)
                ctx.stroke(Self.path(for: mark, in: r), with: .color(Theme.ink.opacity(0.78)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 30, height: 30)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 14.5, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
    }

    private func inkButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text).font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                InkCaret(size: 13, color: Theme.paper.opacity(0.75))
                    .rotationEffect(.degrees(-90))          // a right-pointing caret
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Each guide mark as ink strokes in a unit-ish box.
    private static func path(for mark: Mark, in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        var path = Path()
        switch mark {
        case .pen:
            path.move(to: p(0.10, 0.66))
            path.addQuadCurve(to: p(0.5, 0.5), control: p(0.30, 0.24))
            path.addQuadCurve(to: p(0.90, 0.52), control: p(0.70, 0.76))
        case .cross:
            path.move(to: p(0.18, 0.2)); path.addLine(to: p(0.82, 0.8))
            path.move(to: p(0.82, 0.2)); path.addLine(to: p(0.18, 0.8))
        case .question:
            path.move(to: p(0.28, 0.32))
            path.addCurve(to: p(0.70, 0.33), control1: p(0.30, 0.02), control2: p(0.84, 0.05))
            path.addCurve(to: p(0.50, 0.58), control1: p(0.76, 0.44), control2: p(0.50, 0.44))
            path.addLine(to: p(0.50, 0.64))
            let dot = r.width * 0.05
            path.move(to: p(0.50, 0.82))
            path.addEllipse(in: CGRect(x: p(0.50, 0.82).x - dot, y: p(0.50, 0.82).y - dot, width: dot * 2, height: dot * 2))
        case .vee:
            path.move(to: p(0.22, 0.2)); path.addLine(to: p(0.5, 0.82)); path.addLine(to: p(0.78, 0.2))
        case .zed:
            path.move(to: p(0.2, 0.22)); path.addLine(to: p(0.8, 0.22))
            path.addLine(to: p(0.2, 0.78)); path.addLine(to: p(0.8, 0.78))
        }
        return path
    }
}
