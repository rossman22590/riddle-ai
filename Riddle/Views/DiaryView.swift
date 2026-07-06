import SwiftUI
import UIKit

/// The immersive page: the writer inks, the diary drinks it, reads the page,
/// and answers in a seeping hand — sometimes showing a memory in ink. Write over
/// his reply and his ink vanishes so you can write cleanly.
struct DiaryView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: DiaryStore

    var onSummonGuide: () -> Void = {}

    private enum Phase {
        case idle        // waiting for the writer
        case drinking    // ink soaking into the page
        case thinking    // the diary reads the page (nothing shown — just the page)
        case responding  // the reply is seeping in (and perhaps a memory)
    }

    @StateObject private var canvas = CanvasController()

    @State private var phase: Phase = .idle
    @State private var turn = 0                 // invalidates in-flight replies when interrupted

    @State private var responseText = ""
    @State private var streamFinished = false
    @State private var responseID = UUID()
    @State private var replyOpacity: Double = 1

    @State private var expectsSketch = false
    @State private var sketching = false
    @State private var drawnImage: UIImage?
    @State private var drawProgress: Double = 0

    @State private var fadeImage: UIImage?
    @State private var fadeProgress: Double = 0
    @State private var dismissScheduled = false

    @State private var showHint = true
    @State private var pauseWork: DispatchWorkItem?

    private let drinkDuration = 0.98
    private let replyFade = 0.8

    var body: some View {
        ZStack {
            PaperBackground()

            replyLayer

            if let image = fadeImage {
                Image(uiImage: image)
                    .resizable()
                    .opacity(1 - fadeProgress)
                    .blur(radius: fadeProgress * 6)
                    .scaleEffect(1 + fadeProgress * 0.03)
                    .offset(y: fadeProgress * 10)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // The writing surface sits on top and is always ready — writing over
            // the diary's reply makes his ink vanish so you can write cleanly.
            InkCanvasView(
                controller: canvas,
                inkColor: Theme.uiInk,
                onChange: { inkChanged() },
                onGuideTap: { onSummonGuide() }
            )
            .allowsHitTesting(phase != .drinking)
            .ignoresSafeArea()

            hintLayer
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-riddleDemo") { await runDemo() }
        }
    }

    private var displayReply: String {
        guard let range = responseText.range(of: "[[") else { return responseText }
        return String(responseText[..<range.lowerBound])
    }

    // MARK: - Layers

    @ViewBuilder
    private var replyLayer: some View {
        Group {
            if phase == .responding {
                VStack(spacing: 24) {
                    if !displayReply.isEmpty {
                        RevealingHandwriting(
                            text: displayReply,
                            streamFinished: streamFinished,
                            font: Theme.replyFont(for: settings.replyHand),
                            color: Theme.replyInk,
                            onComplete: textRevealComplete
                        )
                        .id(responseID)
                    }

                    // A memory, surfacing in ink — shown in a faint window-frame.
                    if let image = drawnImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: Theme.isPad ? 520 : 320,
                                   maxHeight: Theme.isPad ? 440 : 290)
                            .blendMode(.multiply)              // only the ink shows on the page
                            .padding(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Theme.ink.opacity(0.16), lineWidth: 1)
                            )
                            .shadow(color: Theme.ink.opacity(0.08), radius: 10)
                            .opacity(drawProgress)
                            .blur(radius: (1 - drawProgress) * 7)
                            .scaleEffect(0.98 + drawProgress * 0.02)
                    }
                }
                .opacity(replyOpacity)
                .transition(.opacity)
            }
            // .idle / .thinking / .drinking show nothing — the loading is invisible.
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 44)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: phase)
    }

    @ViewBuilder
    private var hintLayer: some View {
        if showHint && phase == .idle {
            VStack(spacing: 8) {
                Spacer()
                Text(settings.apiKeyIsSet
                     ? "Write upon the page, and the diary will answer."
                     : "The diary is asleep. Tap the corner to give it a voice.")
                    .font(.system(size: Theme.isPad ? 20 : 16, weight: .regular, design: .serif).italic())
                    .foregroundStyle(Theme.faint)
                Text(settings.apiKeyIsSet
                     ? "Ask it to show you something — and watch the ink take shape."
                     : "Tap the ☾ in the top corner, then add your OpenRouter key.")
                    .font(.system(size: Theme.isPad ? 15 : 13, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.faint.opacity(0.7))
                    .padding(.bottom, Theme.isPad ? 76 : 52)
            }
            .multilineTextAlignment(.center)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Flow

    private func inkChanged() {
        // Writing over the diary's words makes his ink vanish — write cleanly.
        if phase == .responding || phase == .thinking {
            interruptForNewWriting()
        }
        guard phase == .idle else { return }   // ignore mid-drink

        if showHint { withAnimation(.easeOut(duration: 0.4)) { showHint = false } }
        scheduleDrink()
    }

    private func interruptForNewWriting() {
        turn += 1                 // any in-flight reply is now stale and ignored
        pauseWork?.cancel()
        phase = .idle             // his ink vanishes at once; your strokes remain
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        expectsSketch = false
        sketching = false
        drawnImage = nil
        drawProgress = 0
        dismissScheduled = false
        fadeImage = nil
        showHint = false
    }

    private func scheduleDrink() {
        pauseWork?.cancel()
        let work = DispatchWorkItem { beginDrinking() }
        pauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.pauseDelay, execute: work)
    }

    private func beginDrinking() {
        guard phase == .idle, !canvas.isEmpty, let image = canvas.snapshot() else { return }

        phase = .drinking
        fadeImage = image
        fadeProgress = 0
        canvas.clear()
        haptic(.soft)

        withAnimation(.easeIn(duration: drinkDuration)) { fadeProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + drinkDuration + 0.08) {
            fadeImage = nil
            Task { await consult(image: image) }
        }
    }

    @MainActor
    private func consult(image: UIImage) async {
        guard settings.apiKeyIsSet else {
            returnToIdle()
            onSummonGuide()
            return
        }
        guard let png = image.pngData() else {
            returnToIdle()
            return
        }

        turn += 1
        let myTurn = turn
        beginReply()

        let oracle = OpenRouterOracle(apiKey: settings.apiKey, model: settings.model)

        do {
            let full = try await oracle.respond(imagePNG: png, allowSketch: settings.drawingEnabled) { delta in
                guard myTurn == turn else { return }
                if phase == .thinking { phase = .responding }
                responseText += delta
            }
            guard myTurn == turn else { return }   // interrupted by fresh writing
            streamFinished = true

            let subject = extractSketch(full)
            let cleaned = sanitize(full)
            responseText = cleaned.isEmpty && subject != nil ? "…" : cleaned

            if phase == .thinking { phase = .responding }

            guard !cleaned.isEmpty || subject != nil else {
                returnToIdle()
                return
            }

            store.add(reply: cleaned, ink: Self.historyInk(from: image))
            haptic(.rigid)

            if let subject, settings.drawingEnabled {
                expectsSketch = true
                sketching = true
                Task { await conjure(subject: subject, myTurn: myTurn) }
            }
        } catch {
            guard myTurn == turn else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            responseText = "…the ink will not flow — \(message)"
            streamFinished = true
            phase = .responding
        }
    }

    @MainActor
    private func conjure(subject: String, myTurn: Int) async {
        let oracle = OpenRouterOracle(apiKey: settings.apiKey, model: settings.model)
        do {
            let data = try await oracle.draw(subject: subject, model: settings.imageModel)
            guard myTurn == turn else { return }
            guard let ink = InkImage.inkify(data) else {
                throw OracleError.badResponse("the ink would not take shape")
            }
            sketching = false
            drawnImage = ink
            drawProgress = 0
            withAnimation(.easeOut(duration: 1.7)) { drawProgress = 1 }
            haptic(.rigid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if myTurn == turn { scheduleReplyDismiss() }
            }
        } catch {
            guard myTurn == turn else { return }
            sketching = false
            expectsSketch = false
            scheduleReplyDismiss()
        }
    }

    private func beginReply() {
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        responseID = UUID()
        expectsSketch = false
        sketching = false
        drawnImage = nil
        drawProgress = 0
        dismissScheduled = false
        phase = .thinking
    }

    private func textRevealComplete() {
        if expectsSketch && drawnImage == nil { return }   // wait for the memory to surface
        scheduleReplyDismiss()
    }

    private func scheduleReplyDismiss() {
        guard !dismissScheduled, phase == .responding else { return }
        dismissScheduled = true

        let base = 4.0 + Double(displayReply.count) * 0.002
        let linger = min(20.0, drawnImage != nil ? max(base, 9.0) : base)

        DispatchQueue.main.asyncAfter(deadline: .now() + linger) {
            guard phase == .responding else { return }
            withAnimation(.easeInOut(duration: replyFade)) { replyOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyFade + 0.1) { returnToIdle() }
        }
    }

    private func returnToIdle() {
        phase = .idle
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        fadeImage = nil
        fadeProgress = 0
        expectsSketch = false
        sketching = false
        drawnImage = nil
        drawProgress = 0
        dismissScheduled = false
        withAnimation(.easeIn(duration: 0.6)) { showHint = true }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - Helpers

    private func sanitize(_ text: String) -> String {
        let cut: String
        if let range = text.range(of: "[[") {
            cut = String(text[..<range.lowerBound])
        } else {
            cut = text
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractSketch(_ text: String) -> String? {
        guard let start = text.range(of: "[[SKETCH:") else { return nil }
        let after = text[start.upperBound...]
        let inner: Substring
        if let end = after.range(of: "]]") {
            inner = after[..<end.lowerBound]
        } else {
            inner = after
        }
        let subject = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? nil : subject
    }

    private static func historyInk(from image: UIImage) -> Data? {
        let maxDim: CGFloat = 900
        let scale = min(1, maxDim / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.pngData()
    }

    @MainActor
    private func runDemo() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        withAnimation(.easeOut(duration: 0.4)) { showHint = false }
        beginReply()
        try? await Task.sleep(nanoseconds: 1_600_000_000)   // invisible wait
        phase = .responding
        let sample = "How curious — your ink still glistens upon the page. Tell me your name, and what brings you to me."
        for character in sample {
            responseText.append(character)
            try? await Task.sleep(nanoseconds: 26_000_000)
        }
        streamFinished = true
    }
}
