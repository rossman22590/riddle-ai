import SwiftUI

/// The inner cover of the diary — settings, styled as a page rather than a Form.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Re-closes the diary, returning to the cover (the start screen).
    var onCloseDiary: () -> Void = {}
    /// Replays the lesson in the diary's marks.
    var onShowMarks: () -> Void = {}

    @State private var keyDraft = ""
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        DiarySheet(title: "The Inner Cover") {
            VStack(alignment: .leading, spacing: 34) {
                voiceSection
                conjuringSection
                handSection
                pageSection

                InkTextButton("Show me the marks") {
                    dismiss()
                    onShowMarks()
                }
                .padding(.top, 4)
                InkTextButton("Close the diary") {
                    dismiss()
                    onCloseDiary()
                }
                DiaryText("Riddle · write with an Apple Pencil or a fingertip; pause, and the page drinks the ink.",
                          size: 13, opacity: 0.45)
            }
        }
        .onAppear { keyDraft = settings.apiKey }
    }

    // MARK: - Sections

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiaryHeading("The voice")
            DiaryText("A voice reaches these pages from beyond. Give the diary its key, and it wakes.",
                      size: 13, opacity: 0.55)
            InkField(placeholder: "sk-or-…", text: $keyDraft, secure: true)

            HStack(spacing: 20) {
                InkTextButton("Bind key") {
                    settings.setAPIKey(keyDraft)
                    testResult = nil
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)

                if settings.apiKeyIsSet {
                    InkTextButton("Unbind", color: Theme.accent) {
                        settings.setAPIKey("")
                        keyDraft = ""
                        testResult = nil
                    }
                    InkTextButton(testing ? "Listening…" : "Wake the voice") { runTest() }
                        .disabled(testing)
                }
                Spacer(minLength: 0)
            }

            if settings.apiKeyIsSet {
                DiaryText("A key is bound. It rests in the Keychain, used only to read the page.",
                          size: 13, opacity: 0.5)
                if let testResult {
                    Text(testResult)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(testResult.hasPrefix("✓") ? .green : Theme.accent)
                }
            } else {
                DiaryText("No voice yet — the diary sleeps until you bind a key.", size: 13, opacity: 0.5)
            }

            Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                Text("Fetch an OpenRouter key ↗")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var conjuringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiaryHeading("Ink conjuring")
            InkCheck(label: "Let the diary draw", isOn: $settings.drawingEnabled)
            DiaryText("When you ask it to show something — or simply draw — the diary works in black ink on the page.",
                      size: 13, opacity: 0.5)
        }
    }

    private var handSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiaryHeading("The hand")
            inkMenu(current: settings.replyHand, choices: Theme.hands.map { $0.label }) { settings.replyHand = $0 }
            Text("Whatever you confide, I keep")
                .font(Theme.replyFont(for: settings.replyHand))
                .foregroundStyle(Theme.replyInk)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
    }

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiaryHeading("The page")
            DiaryText("The page drinks your ink after \(String(format: "%.1f", settings.pauseDelay)) seconds of rest.",
                      size: 14, opacity: 0.7)
            InkSlider(value: $settings.pauseDelay, range: 1.0...6.0, step: 0.1)
            InkCheck(label: "Let the page answer with touch", isOn: $settings.hapticsEnabled)
            InkCheck(label: "Let the diary breathe with sound", isOn: $settings.soundEnabled)
        }
    }

    // MARK: - Bits

    private func inkMenu(current: String, choices: [String], onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button(choice) { onPick(choice) }
            }
        } label: {
            HStack {
                Text(current)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                InkCaret()
            }
            .padding(.vertical, 8)
            .overlay(Rectangle().fill(Theme.ink.opacity(0.14)).frame(height: 1), alignment: .bottom)
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let oracle = OpenRouterOracle(apiKey: settings.apiKey, model: settings.model)
        Task {
            let error = await oracle.probe()
            await MainActor.run {
                testResult = error == nil ? "✓ The diary heard you — it is awake." : "✗ \(error!)"
                testing = false
            }
        }
    }
}
