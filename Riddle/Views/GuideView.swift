import SwiftUI

/// The built-in guide — summoned by drawing a "?" or a two-finger tap. Rendered
/// as a page of the diary, not an iOS panel.
struct GuideView: View {
    var onSettings: () -> Void
    var onHistory: () -> Void

    var body: some View {
        DiarySheet(title: "Riddle") {
            VStack(alignment: .leading, spacing: 26) {
                DiaryText("Write to me, and rest your pen. I will read your hand and answer in mine.",
                          size: 17, opacity: 0.7)

                VStack(alignment: .leading, spacing: 20) {
                    row("pencil.line", "Write, then rest your pen",
                        "The diary drinks your ink and answers in its own hand.")
                    row("eraser", "Tap the pencil mark to erase",
                        "Or double-tap the Pencil; switch back before the page drinks it.")
                    row("questionmark", "Draw a  ?  on the page",
                        "Summons this guide, at any time.")
                    row("hand.tap", "Tap with two fingers",
                        "Also summons this guide.")
                }

                VStack(spacing: 12) {
                    inkButton("The ink & the voice", "gearshape", action: onSettings)
                    inkButton("The diary's memory", "book.closed", action: onHistory)
                }
                .padding(.top, 8)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .frame(width: 32)
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

    private func inkButton(_ text: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                Text(text).font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).opacity(0.6)
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
