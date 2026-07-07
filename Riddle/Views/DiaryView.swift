import SwiftUI
import UIKit

/// The immersive page: the writer inks, the diary drinks it, reads the page,
/// and answers in a seeping hand — sometimes showing a memory in ink. Write over
/// his reply and his ink vanishes so you can write cleanly.
struct DiaryView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: DiaryStore
    @EnvironmentObject private var session: DiarySession
    @EnvironmentObject private var soul: MemorySoul

    var onSummonGuide: () -> Void = {}

    private enum Phase {
        case idle        // waiting for the writer
        case drinking    // ink soaking into the page
        case thinking    // the diary reads the page silently
        case responding  // the reply is seeping in (and perhaps a memory)
    }

    @StateObject private var canvas = CanvasController()

    @State private var phase: Phase = .idle
    @State private var turn = 0                 // invalidates in-flight replies when interrupted

    @State private var responseText = ""
    @State private var streamFinished = false
    @State private var responseID = UUID()
    @State private var replyOpacity: Double = 1
    @State private var replyAnchor: CGRect?
    @State private var replyHeld = false
    @State private var clearingReply = false
    @State private var replyDismissWork: DispatchWorkItem?

    @State private var expectsSketch = false
    @State private var sketching = false
    @State private var drawnImage: UIImage?
    @State private var drawProgress: Double = 0

    @State private var fadeImage: UIImage?
    @State private var fadeProgress: Double = 0
    @State private var dismissScheduled = false

    @State private var introVisible = false
    @State private var introText = ""
    @State private var introFinished = false
    @State private var introID = UUID()
    @State private var introOpacity: Double = 0
    @State private var introDismissWork: DispatchWorkItem?
    @State private var pauseWork: DispatchWorkItem?
    @State private var idleNudgeWork: DispatchWorkItem?
    @State private var idleNudgeCount = 0
    @State private var sleeping = false

    private let drinkDuration = 0.98
    private let replyFade = 0.8
    private let slowReplyFade = 6.0
    private let replyLinger: TimeInterval = 30
    private let initiativeDelay: TimeInterval = 120
    private let maxIdleNudges = 4
    private let introLinger: TimeInterval = 5
    private let introFade = 3.0

    var body: some View {
        ZStack {
            PaperBackground()

            GeometryReader { proxy in
                replyLayer
                    .frame(width: replyWidth(in: proxy.size))
                    .scaleEffect(replyScale(in: proxy.size))
                    .position(replyPosition(in: proxy.size))
            }

            if let image = fadeImage {
                BlottyDissolveImage(image: image, progress: fadeProgress)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // The writing surface sits on top and is always ready — writing over
            // the diary's reply makes his ink vanish so you can write cleanly.
            InkCanvasView(
                controller: canvas,
                inkColor: Theme.uiInk,
                onChange: { inkChanged() },
                onPageTap: { pageTapped() },
                onGuideTap: { onSummonGuide() },
                onSleepGesture: { putDiaryToSleep() }
            )
            .allowsHitTesting(phase != .drinking)
            .ignoresSafeArea()

            toolToggle
            introLayer
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-riddleDemo") { await runDemo() }
        }
        .onAppear {
            showIntroMessage()
            scheduleIdleNudge()
        }
        .onDisappear {
            idleNudgeWork?.cancel()
            introDismissWork?.cancel()
        }
    }

    private var displayReply: String {
        sanitize(responseText)
    }

    private var hasVisibleReply: Bool {
        !displayReply.isEmpty || drawnImage != nil
    }

    private var introMessage: String {
        if settings.apiKeyIsSet {
            return "Write upon the page, and the diary will answer.\nAsk it to show you something."
        } else {
            return "The diary is asleep.\nTap the moon in the corner to give it a voice."
        }
    }

    private func replyWidth(in size: CGSize) -> CGFloat {
        let available = max(260, size.width - 56)
        return min(760, available)
    }

    private func replyPosition(in size: CGSize) -> CGPoint {
        let width = replyWidth(in: size)
        let scale = replyScale(in: size)
        let halfHeight = estimatedReplyHeight(width: width) * scale / 2
        let x = size.width / 2
        let rawY = size.height / 2
        let y = min(max(rawY, halfHeight + 48), size.height - halfHeight - 48)
        return CGPoint(x: x, y: y)
    }

    private func replyScale(in size: CGSize) -> CGFloat {
        let height = estimatedReplyHeight(width: replyWidth(in: size))
        let available = max(260, size.height - 112)
        guard height > available else { return 1 }
        return max(0.74, available / height)
    }

    private func estimatedReplyHeight(width: CGFloat) -> CGFloat {
        let text = displayReply
        let fontSize: CGFloat = Theme.isPad ? 46 : 32
        let averageGlyphWidth = fontSize * 0.48
        let charsPerLine = max(12, Int(width / averageGlyphWidth))
        let lineCount = max(1, Int(ceil(Double(max(text.count, 1)) / Double(charsPerLine))))
        let textHeight = CGFloat(lineCount) * (Theme.isPad ? 66 : 48)
        let imageHeight: CGFloat = drawnImage == nil ? 0 : (displayReply.isEmpty ? (Theme.isPad ? 560 : 340) : (Theme.isPad ? 430 : 250))
        let spacing: CGFloat = drawnImage == nil || displayReply.isEmpty ? 0 : 18
        return textHeight + imageHeight + spacing
    }

    // MARK: - Layers

    @ViewBuilder
    private var replyLayer: some View {
        Group {
            if phase == .responding || clearingReply || (replyOpacity < 1 && hasVisibleReply) {
                VStack(spacing: drawnImage == nil ? 24 : 14) {
                    if !displayReply.isEmpty {
                        RevealingHandwriting(
                            text: displayReply,
                            streamFinished: streamFinished,
                            uiFont: Theme.replyUIFont(for: settings.replyHand),
                            color: Theme.replyInk,
                            onComplete: textRevealComplete
                        )
                        .id(responseID)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // A memory, surfacing directly from the paper.
                    if let image = drawnImage {
                        let hasReply = !displayReply.isEmpty
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: Theme.isPad ? 620 : 340,
                                   maxHeight: hasReply ? (Theme.isPad ? 430 : 250) : (Theme.isPad ? 560 : 340))
                            .opacity(drawProgress)
                            .blur(radius: (1 - drawProgress) * 7)
                            .scaleEffect(0.98 + drawProgress * 0.02)
                            .offset(y: (1 - drawProgress) * 18)
                    }
                }
                .opacity(replyOpacity)
                .transition(.opacity)
            }
            // .idle / .drinking / .thinking show only the page. The answer
            // itself fades in once the diary has fully formed it.
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 44)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: phase)
    }

    @ViewBuilder
    private var toolToggle: some View {
        VStack {
            HStack {
                Button {
                    canvas.toggleEraser()
                    haptic(canvas.isErasing ? .rigid : .soft)
                } label: {
                    Image(systemName: canvas.isErasing ? "eraser.fill" : "pencil.tip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(canvas.isErasing ? 0.78 : 0.38))
                        .frame(width: 42, height: 42)
                        .background(Theme.paper.opacity(canvas.isErasing ? 0.96 : 0.76), in: Circle())
                        .overlay(Circle().stroke(Theme.ink.opacity(canvas.isErasing ? 0.24 : 0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(canvas.isErasing ? "Erase ink" : "Write ink")
                Spacer()
            }
            Spacer()
        }
        .padding(.leading, 18)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var introLayer: some View {
        if introVisible && phase == .idle && !hasVisibleReply {
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    RevealingHandwriting(
                        text: introText,
                        streamFinished: introFinished,
                        uiFont: Theme.replyUIFont(for: settings.replyHand),
                        color: Theme.replyInk.opacity(0.55),
                        onComplete: introRevealComplete
                    )
                    .id(introID)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: replyWidth(in: proxy.size))
                    Spacer()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .opacity(introOpacity)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Flow

    private func showIntroMessage() {
        guard !ProcessInfo.processInfo.arguments.contains("-riddleDemo") else { return }
        guard !introVisible, phase == .idle, !hasVisibleReply else { return }
        introDismissWork?.cancel()
        introText = introMessage
        introFinished = true
        introID = UUID()
        introOpacity = 0
        introVisible = true
        withAnimation(.easeInOut(duration: 0.8)) { introOpacity = 1 }
    }

    private func introRevealComplete() {
        introDismissWork?.cancel()
        let work = DispatchWorkItem { hideIntroMessage(duration: introFade) }
        introDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + introLinger, execute: work)
    }

    private func hideIntroMessage(duration: Double) {
        introDismissWork?.cancel()
        guard introVisible else { return }
        withAnimation(.easeInOut(duration: duration)) { introOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            guard introOpacity == 0 else { return }
            introVisible = false
            introText = ""
            introFinished = false
        }
    }

    private func inkChanged() {
        cancelIdleNudge()
        hideIntroMessage(duration: 0.35)

        // Writing over the diary's words makes his ink vanish — write cleanly.
        if phase == .responding || phase == .thinking {
            interruptForNewWriting()
        }
        guard phase == .idle else { return }   // ignore mid-drink

        scheduleDrink()
    }

    private func interruptForNewWriting() {
        let shouldFadeReply = hasVisibleReply

        turn += 1                 // any in-flight reply is now stale and ignored
        let interruptedTurn = turn
        pauseWork?.cancel()
        replyDismissWork?.cancel()
        replyHeld = false
        sleeping = false
        phase = .idle             // the page listens again while his ink fades
        streamFinished = true
        expectsSketch = false
        sketching = false
        dismissScheduled = false
        fadeImage = nil
        hideIntroMessage(duration: 0.35)

        if shouldFadeReply {
            clearingReply = true
            withAnimation(.easeOut(duration: 0.22)) {   // his ink retreats quickly beneath yours
                replyOpacity = 0
                drawProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                guard turn == interruptedTurn, phase == .idle else { return }
                responseText = ""
                streamFinished = false
                replyOpacity = 1
                clearingReply = false
                drawnImage = nil
                drawProgress = 0
            }
        } else {
            responseText = ""
            streamFinished = false
            replyOpacity = 1
            clearingReply = false
            drawnImage = nil
            drawProgress = 0
        }
    }

    private func scheduleDrink() {
        pauseWork?.cancel()
        let work = DispatchWorkItem { beginDrinking() }
        pauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.pauseDelay, execute: work)
    }

    private func beginDrinking() {
        guard phase == .idle, !canvas.isEmpty, let image = canvas.snapshot() else { return }

        cancelIdleNudge()
        replyDismissWork?.cancel()
        hideIntroMessage(duration: 0.35)
        replyHeld = false
        replyAnchor = canvas.inkBounds
        let summonsGuide = canvas.looksLikeQuestionMark()
        phase = .drinking
        fadeImage = image
        fadeProgress = 0
        canvas.clear()
        haptic(.soft)

        withAnimation(.easeIn(duration: drinkDuration)) { fadeProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + drinkDuration + 0.08) {
            fadeImage = nil
            if summonsGuide {
                phase = .idle
                onSummonGuide()
                scheduleIdleNudge()
            } else {
                Task { await consult(image: image) }
            }
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
        let profile = soul.profile()

        do {
            // First pass: the live conversation + the writer's soul (always known,
            // so most turns need no second round-trip).
            var full = try await oracle.respond(
                imagePNG: png,
                history: session.turns,
                memoryProfile: profile,
                allowSketch: settings.drawingEnabled
            ) { _ in
                guard myTurn == turn else { return }
            }
            guard myTurn == turn else { return }   // interrupted by fresh writing
            let firstRead = extractRead(full)

            if let recallQuery = extractRecall(full) {
                // Rare: he wants the exact words of a specific past page.
                showGatheringFragment(sanitize(full), myTurn: myTurn)
                let recalled = store.recall(recallQuery)
                full = try await oracle.respond(
                    imagePNG: png,
                    history: session.turns,
                    memoryProfile: profile,
                    preservedMemory: recalled,
                    allowSketch: settings.drawingEnabled
                ) { _ in
                    guard myTurn == turn else { return }
                }
                guard myTurn == turn else { return }
            } else if let webQuery = extractWebRequest(full) ?? freshTraceQuery(from: firstRead) {
                showGatheringFragment(sanitize(full), myTurn: myTurn)
                full = try await oracle.respond(
                    imagePNG: png,
                    history: session.turns,
                    memoryProfile: profile,
                    allowSketch: settings.drawingEnabled,
                    webQuery: webQuery
                ) { _ in
                    guard myTurn == turn else { return }
                }
                guard myTurn == turn else { return }
            }

            let subject = extractSketch(full)
            let redrawInstruction = extractRedraw(full)
            let writer = extractRead(full)
            let cleaned = sanitize(full)

            guard !cleaned.isEmpty || subject != nil || redrawInstruction != nil else {
                returnToIdle()
                return
            }

            // Quietly distil what he learned about the writer into their soul.
            soul.absorb(extractMemory(full))

            responseText = cleaned
            streamFinished = true
            responseID = UUID()               // fresh reveal, even if a wisp was shown while waiting
            withAnimation(.easeInOut(duration: 0.7)) { phase = .responding }

            store.add(writer: writer, reply: cleaned, ink: Self.historyInk(from: image))
            session.add(writer: writer ?? "", reply: cleaned)
            haptic(.rigid)

            if let redrawInstruction, settings.drawingEnabled {
                // Refine the writer's own drawing (image-to-image).
                expectsSketch = true
                sketching = true
                Task { await conjureEdit(instruction: redrawInstruction, source: png, myTurn: myTurn) }
            } else if let subject, settings.drawingEnabled {
                expectsSketch = true
                sketching = true
                Task { await conjure(subject: subject, myTurn: myTurn) }
            } else {
                scheduleReplyDismiss()
                scheduleIdleNudge()
            }
        } catch {
            guard myTurn == turn else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            responseText = "…the ink will not flow — \(message)"
            streamFinished = true
            withAnimation(.easeInOut(duration: 0.7)) { phase = .responding }
            scheduleReplyDismiss()
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
            scheduleReplyDismiss()
            scheduleIdleNudge()
        } catch {
            guard myTurn == turn else { return }
            sketching = false
            expectsSketch = false
            scheduleReplyDismiss()
        }
    }

    @MainActor
    private func conjureEdit(instruction: String, source: Data, myTurn: Int) async {
        let oracle = OpenRouterOracle(apiKey: settings.apiKey, model: settings.model)
        do {
            let data = try await oracle.redraw(instruction: instruction, source: source, model: settings.imageModel)
            guard myTurn == turn else { return }
            guard let ink = InkImage.inkify(data) else {
                throw OracleError.badResponse("the ink would not take shape")
            }
            sketching = false
            drawnImage = ink
            drawProgress = 0
            withAnimation(.easeOut(duration: 1.7)) { drawProgress = 1 }
            haptic(.rigid)
            scheduleReplyDismiss()
            scheduleIdleNudge()
        } catch {
            guard myTurn == turn else { return }
            sketching = false
            expectsSketch = false
            scheduleReplyDismiss()
        }
    }

    private func beginReply() {
        cancelIdleNudge()
        replyDismissWork?.cancel()
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        replyHeld = false
        clearingReply = false
        sleeping = false
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
        scheduleIdleNudge()
    }

    private func scheduleReplyDismiss() {
        replyDismissWork?.cancel()
        guard phase == .responding, hasVisibleReply, !replyHeld, !sleeping else { return }
        dismissScheduled = true
        let work = DispatchWorkItem {
            guard phase == .responding, hasVisibleReply, !replyHeld, !sleeping else { return }
            withAnimation(.easeInOut(duration: slowReplyFade)) {
                replyOpacity = 0
                drawProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + slowReplyFade + 0.1) {
                guard phase == .responding, !replyHeld, !sleeping else { return }
                returnToIdle()
            }
        }
        replyDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + replyLinger, execute: work)
    }

    private func returnToIdle() {
        replyDismissWork?.cancel()
        phase = .idle
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        replyHeld = false
        clearingReply = false
        sleeping = false
        fadeImage = nil
        fadeProgress = 0
        expectsSketch = false
        sketching = false
        drawnImage = nil
        drawProgress = 0
        dismissScheduled = false
        scheduleIdleNudge()
    }

    private func pageTapped() {
        if sleeping {
            returnToIdle()
            return
        }
        guard phase == .responding, hasVisibleReply else { return }
        replyHeld = true
        replyDismissWork?.cancel()
        dismissScheduled = false
        withAnimation(.easeInOut(duration: 0.5)) {
            replyOpacity = 1
            if drawnImage != nil { drawProgress = 1 }
        }
        haptic(.soft)
        scheduleReplyDismiss()
    }

    private func putDiaryToSleep() {
        guard phase != .drinking else { return }
        turn += 1
        pauseWork?.cancel()
        replyDismissWork?.cancel()
        cancelIdleNudge()
        hideIntroMessage(duration: 0.35)
        canvas.clear()
        sleeping = true
        replyHeld = true
        clearingReply = false
        responseText = "The diary sleeps."
        streamFinished = true
        responseID = UUID()
        drawnImage = nil
        drawProgress = 0
        replyOpacity = 0
        withAnimation(.easeInOut(duration: 0.8)) {
            phase = .responding
            replyOpacity = 1
        }
        haptic(.rigid)
    }

    private func scheduleIdleNudge() {
        idleNudgeWork?.cancel()
        guard settings.apiKeyIsSet, idleNudgeCount < maxIdleNudges else { return }
        guard phase == .idle || phase == .responding else { return }

        let work = DispatchWorkItem { showIdleNudge() }
        idleNudgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + initiativeDelay, execute: work)
    }

    private func cancelIdleNudge() {
        idleNudgeWork?.cancel()
        idleNudgeWork = nil
        idleNudgeCount = 0
    }

    private func showIdleNudge() {
        guard settings.apiKeyIsSet, idleNudgeCount < maxIdleNudges else { return }
        guard phase == .idle || phase == .responding else { return }
        guard canvas.isEmpty else {
            scheduleIdleNudge()
            return
        }

        idleNudgeCount += 1
        hideIntroMessage(duration: 0.35)
        let line = spontaneousLine()

        if phase == .responding, hasVisibleReply {
            let existing = displayReply
            responseText = existing.isEmpty ? line : "\(existing)\n\n\(line)"
            streamFinished = true
            withAnimation(.easeInOut(duration: 0.7)) { replyOpacity = 1 }
        } else {
            responseText = line
            streamFinished = true
            responseID = UUID()
            replyOpacity = 0
            drawnImage = nil
            drawProgress = 0
            withAnimation(.easeInOut(duration: 0.7)) {
                phase = .responding
                replyOpacity = 1
            }
        }
        haptic(.soft)
        scheduleIdleNudge()
    }

    private func spontaneousLine() -> String {
        let lines = [
            "Still there, are you?",
            "You have gone very quiet.",
            "Tell me what you did not write.",
            "Ask me what I remember.",
            "There is another way to look at it.",
            "I could show you, if you asked."
        ]
        let index = abs(Int(Date().timeIntervalSince1970)) % lines.count
        return lines[index]
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - Helpers

    private func sanitize(_ text: String) -> String {
        stripMarkdown(from: stripBracketDebris(from: stripVisibleCitations(from: stripHiddenTags(from: text))))
    }

    /// The diary writes in ink, not markup. Strip any markdown the model slips in
    /// (emphasis, code ticks, headings, bullets, links) so only clean prose is inked.
    private func stripMarkdown(from text: String) -> String {
        var result = text

        // [label](url) -> label
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)

        // Emphasis / strikethrough / inline code markers.
        for token in ["**", "__", "~~", "`"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")

        // Line-leading markdown: headings, quotes, bullets, numbered lists.
        let lines = result.components(separatedBy: "\n").map { line -> String in
            var stripped = line
            for pattern in [#"^\s{0,3}#{1,6}\s+"#, #"^\s{0,3}>\s?"#, #"^\s{0,3}[-+•·]\s+"#, #"^\s{0,3}\d+\.\s+"#] {
                stripped = stripped.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            return stripped
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractSketch(_ text: String) -> String? {
        extractHiddenTag("SKETCH", from: text)
    }

    private func extractRead(_ text: String) -> String? {
        extractHiddenTag("READ", from: text)
    }

    private func extractWebRequest(_ text: String) -> String? {
        guard let query = extractHiddenTag("WEB", from: text) else { return nil }
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = cleaned.lowercased()
        guard !["none", "no", "false", "n/a", "not needed"].contains(lowered) else { return nil }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractRecall(_ text: String) -> String? {
        guard let query = extractHiddenTag("RECALL", from: text) else { return nil }
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = cleaned.lowercased()
        guard !["none", "no", "false", "n/a", "not needed", "nothing"].contains(lowered) else { return nil }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractRedraw(_ text: String) -> String? {
        guard let instruction = extractHiddenTag("REDRAW", from: text) else { return nil }
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = cleaned.lowercased()
        guard !["none", "no", "false", "n/a", "not needed", "nothing"].contains(lowered) else { return nil }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractMemory(_ text: String) -> String? {
        guard let facts = extractHiddenTag("MEMORY", from: text) else { return nil }
        let cleaned = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// While a second pass runs, show his first-pass wisp — ink beginning to move
    /// — so the wait feels alive rather than dead. Only a short fragment.
    private func showGatheringFragment(_ fragment: String, myTurn: Int) {
        guard myTurn == turn else { return }
        let wisp = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wisp.isEmpty, wisp.count <= 64 else { return }
        replyDismissWork?.cancel()
        dismissScheduled = false
        responseText = wisp
        streamFinished = false
        responseID = UUID()
        withAnimation(.easeInOut(duration: 0.5)) { phase = .responding }
    }

    private func freshTraceQuery(from text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let freshNeedles = [
            "today", "tonight", "tomorrow", "yesterday", "right now", "currently",
            "current", "latest", "newest", "recent", "this week", "this month",
            "this year", "2026", "news", "headline", "trending", "happened",
            "look up", "search", "internet", "web", "online", "source",
            "weather", "forecast", "score", "standings", "won", "price", "cost",
            "stock", "market", "release", "released", "available", "president",
            "prime minister", "ceo", "mayor", "governor", "election"
        ]

        guard freshNeedles.contains(where: { lowered.contains($0) }) else { return nil }
        return String(trimmed.prefix(180))
    }

    private func extractHiddenTag(_ name: String, from text: String) -> String? {
        guard let start = text.range(of: "[[\(name):") else { return nil }
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

    private func stripHiddenTags(from text: String) -> String {
        var cleaned = text
        while let start = cleaned.range(of: "[[") {
            if let end = cleaned[start.lowerBound...].range(of: "]]") {
                cleaned.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                cleaned.removeSubrange(start.lowerBound..<cleaned.endIndex)
            }
        }
        for marker in ["[READ:", "[SKETCH:", "[WEB:", "[RECALL:", "[REDRAW:", "[MEMORY:", "READ:", "SKETCH:", "WEB:", "RECALL:", "REDRAW:", "MEMORY:"] {
            if let range = cleaned.range(of: marker, options: .caseInsensitive) {
                cleaned.removeSubrange(range.lowerBound..<cleaned.endIndex)
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripVisibleCitations(from text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(https?://[^\\s)]+\\)",
            with: "$1",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "https?://\\S+",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\s*\\[[0-9,\\s]+\\]",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\s*【[^】]*】",
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripBracketDebris(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "\\s*\\[(?:source|sources|citation|citations)[^\\]]*\\]\\s*$",
            "\\s*\\[[^\\]\\n]{0,120}$",
            "\\s*【[^】\\n]{0,120}$",
            "\\s*[\\[\\]【】]+\\s*$"
        ]

        var changed = true
        while changed {
            let before = cleaned
            for pattern in patterns {
                cleaned = cleaned.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            changed = cleaned != before
        }

        return cleaned
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
        hideIntroMessage(duration: 0.35)
        beginReply()
        try? await Task.sleep(nanoseconds: 1_600_000_000)   // silent wait
        let sample = "How curious — your ink still glistens upon the page. Tell me your name, and what brings you to me."
        responseText = sample
        streamFinished = true
        withAnimation(.easeInOut(duration: 0.7)) { phase = .responding }
    }
}

private struct BlottyDissolveImage: View {
    let image: UIImage
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .blendMode(.multiply)
                .opacity(max(0, 1 - progress * 0.82))
                .blur(radius: progress * 4.5)
                .scaleEffect(1 + progress * 0.025)
                .offset(y: progress * 10)
                .mask {
                    dissolveMask(in: proxy.size)
                }
        }
    }

    private func dissolveMask(in size: CGSize) -> some View {
        ZStack {
            Color.white
            ForEach(0..<84, id: \.self) { index in
                let threshold = Double(seed(index, 7))
                let bloom = min(1, max(0, (progress - threshold) * 3.6))
                if bloom > 0 {
                    Ellipse()
                        .fill(Color.black.opacity(bloom))
                        .frame(
                            width: (26 + seed(index, 13) * 150) * bloom,
                            height: (18 + seed(index, 29) * 110) * bloom
                        )
                        .rotationEffect(.degrees(Double(seed(index, 41) * 180)))
                        .position(
                            x: seed(index, 61) * size.width,
                            y: seed(index, 83) * size.height
                        )
                }
            }
        }
        .luminanceToAlpha()
    }

    private func seed(_ index: Int, _ salt: Int) -> CGFloat {
        CGFloat((index * 73 + salt * 151) % 997) / 997
    }
}
