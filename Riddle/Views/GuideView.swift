import SwiftUI

/// The built-in guide — summoned by drawing a "?" or a two-finger tap, exactly
/// as in the original (which has no on-screen buttons). It explains the
/// gestures and is the way into Settings and the diary's memory.
struct GuideView: View {
    var onSettings: () -> Void
    var onHistory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Riddle")
                        .font(Theme.display(Theme.isPad ? 56 : 44))
                        .foregroundStyle(Theme.replyInk)
                        .padding(.top, 12)

                    VStack(spacing: 18) {
                        row("pencil.line", "Write, then rest your pen",
                            "The diary drinks your ink and answers in its own hand.")
                        row("eraser", "Flip the pencil, or use the eraser",
                            "Rub out ink before it is drunk.")
                        row("questionmark", "Draw a  ?  on the page",
                            "Summons this guide, at any time.")
                        row("hand.tap", "Tap with two fingers",
                            "Also summons this guide.")
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 12) {
                        Button(action: onSettings) {
                            label("The ink & the voice", systemImage: "gearshape")
                        }
                        Button(action: onHistory) {
                            label("The diary's memory", systemImage: "book.closed")
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            .background(Theme.paper)
            .scrollContentBackground(.hidden)
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.ink.opacity(0.8))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(text).font(.system(size: 17, weight: .medium, design: .serif))
            Spacer()
            Image(systemName: "chevron.right").font(.footnote)
        }
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
