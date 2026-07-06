import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""
    @State private var testing = false
    @State private var testResult: String?

    // Must be vision-capable — the diary reads your handwriting from the page.
    private let modelPresets = [
        "anthropic/claude-haiku-4.5",
        "anthropic/claude-3.7-sonnet",
        "openai/gpt-4o-mini",
        "openai/gpt-4o",
        "google/gemini-2.0-flash-001",
        "google/gemini-2.5-flash",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-or-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Save key") { settings.setAPIKey(keyDraft); testResult = nil }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.apiKeyIsSet {
                            Spacer()
                            Button("Remove", role: .destructive) {
                                settings.setAPIKey("")
                                keyDraft = ""
                                testResult = nil
                            }
                        }
                    }
                    if settings.apiKeyIsSet {
                        Label("Key saved.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                        Button {
                            runTest()
                        } label: {
                            HStack {
                                if testing { ProgressView().controlSize(.small) }
                                Text(testing ? "Listening…" : "Test the diary's voice")
                            }
                        }
                        .disabled(testing)
                        if let testResult {
                            Text(testResult)
                                .font(.footnote)
                                .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                        }
                    } else {
                        Label("No key yet — the diary sleeps until you give it a voice.", systemImage: "moon.zzz")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Link("Get an OpenRouter key ↗", destination: URL(string: "https://openrouter.ai/keys")!)
                        .font(.footnote)
                } header: {
                    Text("OpenRouter")
                } footer: {
                    Text("Your key is stored securely in the device Keychain and sent only to openrouter.ai. The diary reads the ink on the page with a vision model — nothing else.")
                }

                Section {
                    TextField("model slug", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("Choose a model") {
                        ForEach(modelPresets, id: \.self) { preset in
                            Button(preset) { settings.model = preset }
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Must be a vision-capable model — it reads your handwriting from the page.")
                }

                Section {
                    Toggle("Let the diary draw", isOn: $settings.drawingEnabled)
                    if settings.drawingEnabled {
                        TextField("image model", text: $settings.imageModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Illustrations")
                } footer: {
                    Text("When you ask it to draw, the diary sketches — always in black ink, never colour. Uses an image-generation model (default google/gemini-3.1-flash-lite-image).")
                }

                Section("The diary's hand") {
                    Picker("Script", selection: $settings.replyHand) {
                        ForEach(Theme.hands, id: \.label) { hand in
                            Text(hand.label).tag(hand.label)
                        }
                    }
                    Text("The quick brown fox")
                        .font(Theme.replyFont(for: settings.replyHand))
                        .foregroundStyle(Theme.replyInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }

                Section("The ink") {
                    VStack(alignment: .leading) {
                        Text("Pause before the ink is drunk: \(settings.pauseDelay, specifier: "%.1f")s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.pauseDelay, in: 1.0...4.0, step: 0.1)
                    }
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Button("Replay the introduction") { settings.hasOnboarded = false; dismiss() }
                } footer: {
                    Text("Riddle · an enchanted diary for iPad. Write with your Apple Pencil or a fingertip; pause, and your words fade as the diary drinks the ink and answers in flowing script.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { keyDraft = settings.apiKey }
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
