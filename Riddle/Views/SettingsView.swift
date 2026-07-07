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
                        Button("Bind key") { settings.setAPIKey(keyDraft); testResult = nil }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.apiKeyIsSet {
                            Spacer()
                            Button("Unbind", role: .destructive) {
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
                                Text(testing ? "Listening…" : "Wake the voice")
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
                    Link("Fetch an OpenRouter key ↗", destination: URL(string: "https://openrouter.ai/keys")!)
                        .font(.footnote)
                } header: {
                    Text("The voice")
                } footer: {
                    Text("The bound key stays in the device Keychain. It is used only when the diary reads the page.")
                }

                Section {
                    TextField("voice inscription", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("Choose a voice") {
                        ForEach(modelPresets, id: \.self) { preset in
                            Button(preset) { settings.model = preset }
                        }
                    }
                } header: {
                    Text("The spirit")
                } footer: {
                    Text("The spirit must be able to see ink on the page.")
                }

                Section {
                    Toggle("Let the diary draw", isOn: $settings.drawingEnabled)
                    if settings.drawingEnabled {
                        TextField("ink conjuring inscription", text: $settings.imageModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Ink conjuring")
                } footer: {
                    Text("When you ask it to show something, the diary sketches in black ink on cream paper.")
                }

                Section("The hand") {
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

                Section("The page") {
                    VStack(alignment: .leading) {
                        Text("The page drinks after: \(settings.pauseDelay, specifier: "%.1f")s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.pauseDelay, in: 1.0...4.0, step: 0.1)
                        Text("This controls only when your writing sinks into the page.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Let the page answer with touch", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Button("Open the first page again") { settings.hasOnboarded = false; dismiss() }
                } footer: {
                    Text("Riddle · write with Apple Pencil or a fingertip; pause, and the page drinks the ink.")
                }
            }
            .navigationTitle("The Inner Cover")
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
