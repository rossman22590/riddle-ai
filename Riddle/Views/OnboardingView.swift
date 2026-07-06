import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "book.closed.fill",
             title: "Riddle",
             body: "An enchanted diary. Write to it, and it writes back — in flowing script that appears as though penned by an unseen hand."),
        Page(symbol: "pencil.and.scribble",
             title: "Write on the page",
             body: "Use your Apple Pencil or a fingertip. Ask a question, confide a secret, or simply say hello."),
        Page(symbol: "drop.fill",
             title: "The diary drinks your ink",
             body: "Pause for a moment. Your words fade into the paper — and the diary begins to consider them."),
        Page(symbol: "sparkles",
             title: "It answers",
             body: "A reply is written back to you, stroke by stroke. Add your OpenRouter key in Settings for a truly awake diary, or begin now in its dreaming, offline voice."),
    ]

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 26) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(Theme.ink.opacity(0.82))
                            Text(item.title)
                                .font(Theme.display(Theme.isPad ? 66 : 50))
                                .foregroundStyle(Theme.replyInk)
                            Text(item.body)
                                .font(.system(size: Theme.isPad ? 21 : 17, weight: .regular, design: .serif))
                                .foregroundStyle(Theme.ink.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: 560)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: onFinish) {
                    Text(page == pages.count - 1 ? "Begin" : "Skip")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.paper)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: Capsule())
                }
                .padding(.bottom, 60)
            }
        }
    }
}
