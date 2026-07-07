import SwiftUI

/// A sheet that reads as a page of the diary rather than an iOS panel — cream
/// paper, a hand-inked title, a quiet close mark, and no grey Form/List chrome.
struct DiarySheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Text(title)
                        .font(Theme.display(Theme.isPad ? 46 : 34))
                        .foregroundStyle(Theme.replyInk)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            DrawnX(size: 17, color: Theme.ink.opacity(0.5))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Rectangle()
                    .fill(Theme.ink.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                ScrollView {
                    content()
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                }
            }
        }
        .presentationBackground(Theme.paper)
        .tint(Theme.accent)
    }
}

/// A hand-inked section heading for diary pages.
struct DiaryHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.display(Theme.isPad ? 30 : 25))
            .foregroundStyle(Theme.replyInk.opacity(0.92))
    }
}

/// Plain serif body text, in ink, at a chosen weight/opacity.
struct DiaryText: View {
    let text: String
    var size: CGFloat = 16
    var opacity: Double = 0.82
    init(_ text: String, size: CGFloat = 16, opacity: Double = 0.82) {
        self.text = text; self.size = size; self.opacity = opacity
    }
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(Theme.ink.opacity(opacity))
    }
}

/// An ink-underlined text field, so inputs feel written on the page.
struct InkField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 16, weight: .regular, design: .serif))
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 8)
        .overlay(
            Rectangle().fill(Theme.ink.opacity(0.22)).frame(height: 1),
            alignment: .bottom
        )
    }
}

/// Two crossed ink strokes — a hand-drawn close mark, in place of an SF symbol.
struct DrawnX: View {
    var size: CGFloat = 18
    var color: Color = Theme.ink.opacity(0.5)

    var body: some View {
        Canvas { ctx, s in
            let m = s.width * 0.2
            var p = Path()
            p.move(to: CGPoint(x: m, y: m)); p.addLine(to: CGPoint(x: s.width - m, y: s.height - m))
            p.move(to: CGPoint(x: s.width - m, y: m)); p.addLine(to: CGPoint(x: m, y: s.height - m))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: max(1.6, s.width * 0.1), lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// A small inked down-caret ( ⌄ ) — replaces the SF chevron on menus.
struct InkCaret: View {
    var size: CGFloat = 14
    var color: Color = Theme.ink.opacity(0.4)

    var body: some View {
        Canvas { ctx, s in
            var p = Path()
            p.move(to: CGPoint(x: s.width * 0.2, y: s.height * 0.38))
            p.addLine(to: CGPoint(x: s.width * 0.5, y: s.height * 0.66))
            p.addLine(to: CGPoint(x: s.width * 0.8, y: s.height * 0.38))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// A toggle drawn as an inked box that a hand-drawn check fills when on —
/// replaces the green iOS switch that broke the page's spell.
struct InkCheck: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            HStack(spacing: 14) {
                Text(label)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Theme.ink.opacity(0.5), lineWidth: 1.4)
                        .frame(width: 26, height: 26)
                    if isOn {
                        Canvas { ctx, s in
                            var p = Path()
                            p.move(to: CGPoint(x: s.width * 0.2, y: s.height * 0.54))
                            p.addLine(to: CGPoint(x: s.width * 0.42, y: s.height * 0.76))
                            p.addLine(to: CGPoint(x: s.width * 0.82, y: s.height * 0.24))
                            ctx.stroke(p, with: .color(Theme.replyInk),
                                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        }
                        .frame(width: 26, height: 26)
                        .transition(.opacity)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A slider drawn as an ink line with a wet-ink knob, so even the page's
/// settings feel written rather than dialed on an iOS control.
struct InkSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let frac = CGFloat((value - range.lowerBound) / span)
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.ink.opacity(0.16)).frame(height: 1.5)
                Rectangle().fill(Theme.ink.opacity(0.5))
                    .frame(width: max(0, frac * w), height: 1.5)
                Circle()
                    .fill(Theme.replyInk)
                    .frame(width: 17, height: 17)
                    .overlay(Circle().fill(Theme.paper.opacity(0.3)).frame(width: 5, height: 5).offset(x: -2, y: -2.2))
                    .offset(x: max(0, min(w - 17, frac * w - 8.5)))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(1, max(0, g.location.x / w))
                    let raw = range.lowerBound + Double(f) * span
                    value = (raw / step).rounded() * step
                }
            )
        }
        .frame(height: 30)
    }
}

/// A small ink text button on the page.
struct InkTextButton: View {
    let title: String
    var color: Color = Theme.ink
    let action: () -> Void

    init(_ title: String, color: Color = Theme.ink, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}
