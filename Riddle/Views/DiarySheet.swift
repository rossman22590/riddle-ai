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
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink.opacity(0.45))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
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
