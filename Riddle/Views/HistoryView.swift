import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing written yet",
                        systemImage: "book.closed",
                        description: Text("What you write to the diary — and what it answers — is kept here.")
                    )
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                if let data = entry.ink, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: 120, alignment: .leading)
                                        .opacity(0.85)
                                }
                                Text(entry.reply)
                                    .font(Theme.display(28))
                                    .foregroundStyle(Theme.replyInk)
                                Text(entry.date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .listRowBackground(Theme.paper)
                        }
                        .onDelete { indexSet in
                            for index in indexSet { store.delete(store.entries[index]) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.paper)
                }
            }
            .navigationTitle("The Diary's Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) { store.clear() }
                    }
                }
            }
        }
    }
}
