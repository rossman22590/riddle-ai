import SwiftUI

/// The diary's memory — past exchanges, rendered as pages rather than a list.
struct HistoryView: View {
    @EnvironmentObject private var store: DiaryStore
    @EnvironmentObject private var soul: MemorySoul

    var body: some View {
        DiarySheet(title: "The Diary's Memory") {
            if store.entries.isEmpty && soul.facts.isEmpty {
                VStack(spacing: 12) {
                    Text("These pages are yet unwritten.")
                        .font(Theme.display(Theme.isPad ? 34 : 28))
                        .foregroundStyle(Theme.replyInk.opacity(0.7))
                    DiaryText("What you confide, and what the diary answers, is kept here.",
                              size: 15, opacity: 0.55)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Clear-all sits at the top, above the kept pages.
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            store.clear()
                            soul.forget()
                        } label: {
                            Text("Clear all")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 18)

                    ForEach(store.entries) { entry in
                        entryView(entry)
                        if entry.id != store.entries.last?.id {
                            Rectangle()
                                .fill(Theme.ink.opacity(0.07))
                                .frame(height: 1)
                                .padding(.vertical, 20)
                        }
                    }
                }
            }
        }
    }

    private func entryView(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if let writer = entry.writer, !writer.isEmpty {
                    DiaryText("“\(writer)”", size: 15, opacity: 0.55)
                } else {
                    DiaryText(entry.date, size: 13, opacity: 0.4)
                }
                Spacer()
                Button { store.delete(entry) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.3))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let data = entry.ink, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 150, alignment: .leading)
            }

            Text(entry.reply)
                .font(Theme.display(Theme.isPad ? 32 : 26))
                .foregroundStyle(Theme.replyInk)
        }
    }
}

private extension DiaryText {
    init(_ date: Date, size: CGFloat, opacity: Double) {
        self.init(date.formatted(date: .abbreviated, time: .shortened), size: size, opacity: opacity)
    }
}
