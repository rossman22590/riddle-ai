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
    var onOpenMemory: () -> Void = {}

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
    @State private var replyRevealComplete = false
    @State private var imageRevealComplete = true
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
                replyLayer(in: proxy.size)
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
            return "Write upon the page,\nand I will answer."
        } else {
            return "My voice still sleeps.\nWrite, and I will show you how to wake me."
        }
    }

    private func replyWidth(in size: CGSize) -> CGFloat {
        let available = max(260, size.width - 56)
        return min(760, available)
    }

    private struct ReplyFit {
        var width: CGFloat
        var textWidth: CGFloat
        var font: UIFont
        var imageSize: CGSize
        var spacing: CGFloat
        var contentHeight: CGFloat
    }

    private func replyFit(in size: CGSize) -> ReplyFit {
        let width = replyWidth(in: size)
        let textWidth = max(220, width - 88)
        let availableHeight = max(220, size.height - 112)
        let text = displayReply
        let hasText = !text.isEmpty
        let hasImage = drawnImage != nil
        // While a drawing is still being conjured we reserve its box and show a
        // stir there, so the wait before it blooms isn't silent dead air.
        let awaitingImage = drawnImage == nil && sketching
        let reserveImage = hasImage || awaitingImage
        let baseFont = Theme.replyUIFont(for: settings.replyHand)
        let spacing: CGFloat = hasText && reserveImage ? 14 : 0
        // In landscape the page is wide but short — size the ink by the whole
        // width (not the narrow reading column), and let it claim far more of
        // the height so a drawing never shrinks to a stamp.
        let landscape = size.width > size.height
        let maxImageWidth = min(size.width - 48,
                                Theme.isPad ? (landscape ? 900 : 620) : (landscape ? 620 : 340))
        let preferredImageHeight: CGFloat = {
            guard reserveImage else { return 0 }
            // A cap only — if the reply text is long it takes its share first and
            // the image shrinks to fit; when it's a short caption (as it is when
            // he draws) the ink grows into most of the page, even in landscape.
            if hasText {
                return min(availableHeight * (landscape ? 0.82 : 0.44),
                           Theme.isPad ? (landscape ? 740 : 430) : (landscape ? 470 : 250))
            }
            return min(availableHeight * 0.92,
                       Theme.isPad ? (landscape ? 800 : 560) : (landscape ? 480 : 340))
        }()

        guard hasText else {
            let imageSize = imageBoxSize(maxWidth: maxImageWidth, maxHeight: preferredImageHeight, awaitingImage: awaitingImage)
            return ReplyFit(
                width: max(width, imageSize.width + 32),
                textWidth: textWidth,
                font: baseFont,
                imageSize: imageSize,
                spacing: 0,
                contentHeight: max(1, imageSize.height)
            )
        }

        var low: CGFloat = Theme.isPad ? 0.32 : 0.38
        var high: CGFloat = 1
        var best = candidateReplyFit(
            scale: low,
            baseFont: baseFont,
            text: text,
            textWidth: textWidth,
            maxImageWidth: maxImageWidth,
            preferredImageHeight: preferredImageHeight,
            spacing: spacing,
            availableHeight: availableHeight,
            awaitingImage: awaitingImage
        )

        for _ in 0..<12 {
            let mid = (low + high) / 2
            let candidate = candidateReplyFit(
                scale: mid,
                baseFont: baseFont,
                text: text,
                textWidth: textWidth,
                maxImageWidth: maxImageWidth,
                preferredImageHeight: preferredImageHeight,
                spacing: spacing,
                availableHeight: availableHeight,
                awaitingImage: awaitingImage
            )

            if candidate.contentHeight <= availableHeight {
                best = candidate
                low = mid
            } else {
                high = mid
            }
        }

        if best.contentHeight > availableHeight {
            let extraScale = max(0.2, availableHeight / max(best.contentHeight, 1))
            best = candidateReplyFit(
                scale: (Theme.isPad ? 0.32 : 0.38) * extraScale,
                baseFont: baseFont,
                text: text,
                textWidth: textWidth,
                maxImageWidth: maxImageWidth,
                preferredImageHeight: preferredImageHeight,
                spacing: spacing,
                availableHeight: availableHeight,
                awaitingImage: awaitingImage
            )
        }

        return ReplyFit(
            width: max(width, best.imageSize.width + 32),
            textWidth: textWidth,
            font: best.font,
            imageSize: best.imageSize,
            spacing: reserveImage ? spacing : 0,
            contentHeight: min(availableHeight, max(1, best.contentHeight))
        )
    }

    private func candidateReplyFit(
        scale: CGFloat,
        baseFont: UIFont,
        text: String,
        textWidth: CGFloat,
        maxImageWidth: CGFloat,
        preferredImageHeight: CGFloat,
        spacing: CGFloat,
        availableHeight: CGFloat,
        awaitingImage: Bool
    ) -> (font: UIFont, imageSize: CGSize, contentHeight: CGFloat) {
        let pointSize = max(10, baseFont.pointSize * scale)
        let font = UIFont(name: baseFont.fontName, size: pointSize) ?? baseFont.withSize(pointSize)
        let textHeight = makeInkLayout(text: text, font: font, maxWidth: textWidth).size.height
        let reserve = drawnImage != nil || awaitingImage
        let remainingForImage = reserve ? max(0, availableHeight - textHeight - spacing) : 0
        let imageHeight = reserve ? min(preferredImageHeight, remainingForImage) : 0
        let imageSize = imageBoxSize(maxWidth: maxImageWidth, maxHeight: imageHeight, awaitingImage: awaitingImage)
        let total = textHeight + (reserve && imageSize.height > 0 ? spacing : 0) + imageSize.height
        return (font, imageSize, total)
    }

    /// The box for the drawing — the real image once it exists, or a square
    /// placeholder (for the stir) while it is still being conjured.
    private func imageBoxSize(maxWidth: CGFloat, maxHeight: CGFloat, awaitingImage: Bool) -> CGSize {
        if drawnImage != nil { return fittedImageSize(maxWidth: maxWidth, maxHeight: maxHeight) }
        guard awaitingImage, maxWidth > 1, maxHeight > 1 else { return .zero }
        let side = min(maxWidth, maxHeight)
        return CGSize(width: side, height: side)
    }

    private func fittedImageSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard let image = drawnImage, maxWidth > 1, maxHeight > 1, image.size.width > 1, image.size.height > 1 else {
            return .zero
        }

        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    // MARK: - Layers

    @ViewBuilder
    private func replyLayer(in size: CGSize) -> some View {
        let fit = replyFit(in: size)

        Group {
            if phase == .thinking && !hasVisibleReply {
                // The page stirs while he reads — ink welling up where the
                // answer will form, so the silence never reads as "nothing".
                PageStir()
                    .transition(.opacity)
            } else if phase == .responding || clearingReply || (replyOpacity < 1 && hasVisibleReply) {
                VStack(spacing: fit.spacing) {
                    if !displayReply.isEmpty {
                        RevealingHandwriting(
                            text: displayReply,
                            streamFinished: streamFinished,
                            uiFont: fit.font,
                            maxWidth: fit.textWidth,
                            color: Theme.replyInk,
                            haptics: settings.hapticsEnabled,
                            onComplete: textRevealComplete
                        )
                        .id(responseID)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // A memory, surfacing directly from the paper — or, while it
                    // is still forming, the page stirring where it will bloom.
                    if let image = drawnImage {
                        InkBloomImage(image: image, progress: drawProgress)
                            .frame(width: fit.imageSize.width, height: fit.imageSize.height)
                            .offset(y: (1 - drawProgress) * 18)
                    } else if sketching, fit.imageSize.height > 1 {
                        PageStir()
                            .frame(width: fit.imageSize.width, height: fit.imageSize.height)
                    }
                }
                .frame(width: fit.width, height: fit.contentHeight)
                .opacity(replyOpacity)
                .transition(.opacity)
            }
            // .idle / .drinking / .thinking show only the page. The answer
            // itself fades in once the diary has fully formed it.
        }
        .frame(width: fit.width, height: fit.contentHeight)
        .position(x: size.width / 2, y: size.height / 2)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: phase)
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
                        maxWidth: max(220, replyWidth(in: proxy.size) - 88),
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
        DiarySounds.shared.stop("quill", fade: 0.15)
        replyHeld = false
        sleeping = false
        phase = .idle             // the page listens again while his ink fades
        streamFinished = true
        expectsSketch = false
        sketching = false
        replyRevealComplete = true
        imageRevealComplete = true
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
                replyRevealComplete = false
                imageRevealComplete = true
                drawnImage = nil
                drawProgress = 0
            }
        } else {
            responseText = ""
            streamFinished = false
            replyOpacity = 1
            clearingReply = false
            replyRevealComplete = false
            imageRevealComplete = true
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
        let ritual = canvas.detectedRitual()
        phase = .drinking
        fadeImage = image
        fadeProgress = 0
        canvas.clear()
        haptic(.soft)
        DiarySounds.shared.play("drink", volume: 0.4)

        withAnimation(.easeIn(duration: drinkDuration)) { fadeProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + drinkDuration + 0.08) {
            fadeImage = nil
            if let ritual {
                performRitual(ritual)
            } else {
                Task { await consult(image: image) }
            }
        }
    }

    private func performRitual(_ ritual: PageRitual) {
        switch ritual {
        case .guide:
            returnToIdle()
            onSummonGuide()
            haptic(.soft)
        case .erase:
            turn += 1
            returnToIdle()
            haptic(.rigid)
        case .sleep:
            phase = .idle
            putDiaryToSleep()
        case .memory:
            returnToIdle()
            onOpenMemory()
            haptic(.soft)
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
        let oldPages = store.preservedMemoryContext(limit: 5, excludingLiveTurns: session.turns)

        do {
            // First pass: live conversation, the writer's soul, and a few old
            // pages so a newly opened diary still feels continuous.
            var full = try await oracle.respond(
                imagePNG: png,
                history: session.turns,
                memoryProfile: profile,
                preservedMemory: oldPages,
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
                let memory = [oldPages, recalled]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\nA deeper page rises:\n")
                full = try await oracle.respond(
                    imagePNG: png,
                    history: session.turns,
                    memoryProfile: profile,
                    preservedMemory: memory.isEmpty ? nil : memory,
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
                    preservedMemory: oldPages,
                    allowSketch: settings.drawingEnabled,
                    webQuery: webQuery
                ) { _ in
                    guard myTurn == turn else { return }
                }
                guard myTurn == turn else { return }
            }

            let redrawInstruction = extractRedraw(full)
            // If the writer plainly asked to draw, guarantee a drawing even when
            // he didn't tag it himself (as long as there's no redraw of their ink).
            let subject = extractSketch(full)
                ?? (redrawInstruction == nil ? forcedSketchSubject(from: firstRead) : nil)
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
            replyRevealComplete = cleaned.isEmpty
            imageRevealComplete = true
            responseID = UUID()               // fresh reveal, even if a wisp was shown while waiting
            withAnimation(.easeInOut(duration: 0.7)) { phase = .responding }

            store.add(writer: writer, reply: cleaned, ink: Self.historyInk(from: image))
            session.add(writer: writer ?? "", reply: cleaned)
            haptic(.rigid)

            if let redrawInstruction, settings.drawingEnabled {
                // Refine the writer's own drawing (image-to-image).
                expectsSketch = true
                sketching = true
                imageRevealComplete = false
                Task { await conjureEdit(instruction: redrawInstruction, source: png, myTurn: myTurn) }
            } else if let subject, settings.drawingEnabled {
                expectsSketch = true
                sketching = true
                imageRevealComplete = false
                Task { await conjure(subject: subject, myTurn: myTurn) }
            } else {
                scheduleReplyDismiss()
                scheduleIdleNudge()
            }
        } catch {
            guard myTurn == turn else { return }
            // Stay in character — never spill a raw error onto the page.
            responseText = "…the ink scatters before it reaches the page. Rest your pen a moment, then write to me again."
            streamFinished = true
            replyRevealComplete = false
            imageRevealComplete = true
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
            imageRevealComplete = false
            withAnimation(.easeOut(duration: 2.25)) { drawProgress = 1 }
            haptic(.rigid)
            finishImageRevealAfterBloom(myTurn: myTurn)
            scheduleIdleNudge()
        } catch {
            guard myTurn == turn else { return }
            sketching = false
            expectsSketch = false
            imageRevealComplete = true
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
            imageRevealComplete = false
            withAnimation(.easeOut(duration: 2.25)) { drawProgress = 1 }
            haptic(.rigid)
            finishImageRevealAfterBloom(myTurn: myTurn)
            scheduleIdleNudge()
        } catch {
            guard myTurn == turn else { return }
            sketching = false
            expectsSketch = false
            imageRevealComplete = true
            scheduleReplyDismiss()
        }
    }

    private func finishImageRevealAfterBloom(myTurn: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35) {
            guard myTurn == turn, phase == .responding else { return }
            imageRevealComplete = true
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
        replyRevealComplete = false
        imageRevealComplete = true
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
        replyRevealComplete = true
        DiarySounds.shared.stop("quill")
        scheduleReplyDismiss()
        scheduleIdleNudge()
    }

    private func scheduleReplyDismiss() {
        replyDismissWork?.cancel()
        guard phase == .responding, hasVisibleReply, !replyHeld, !sleeping else { return }
        guard streamFinished, replyRevealComplete, imageRevealComplete else { return }
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
        DiarySounds.shared.stop("quill", fade: 0.15)
        phase = .idle
        responseText = ""
        streamFinished = false
        replyOpacity = 1
        replyHeld = false
        clearingReply = false
        replyRevealComplete = false
        imageRevealComplete = true
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
        replyRevealComplete = false
        imageRevealComplete = true
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
            replyDismissWork?.cancel()
            dismissScheduled = false
            let existing = displayReply
            responseText = existing.isEmpty ? line : "\(existing)\n\n\(line)"
            streamFinished = true
            replyRevealComplete = false
            withAnimation(.easeInOut(duration: 0.7)) { replyOpacity = 1 }
        } else {
            responseText = line
            streamFinished = true
            responseID = UUID()
            replyRevealComplete = false
            imageRevealComplete = true
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
        let general = [
            "Still there, are you?",
            "You have gone very quiet.",
            "Tell me what you did not write.",
            "There is another way to look at it.",
            "I could show you, if you asked.",
            "Say something. I do so like to listen.",
        ]
        // Once he has come to know the writer, he reaches back as one who remembers.
        let remembering = [
            "I have not forgotten what you told me.",
            "Ask me what I remember of you.",
            "I was thinking of you, oddly enough.",
            "The page still holds your last words.",
        ]
        let pool = soul.facts.isEmpty ? general : general + remembering
        // Vary with each nudge (and the hour) so the initiative never repeats itself.
        let index = (idleNudgeCount + abs(Int(Date().timeIntervalSince1970) / 7)) % pool.count
        return pool[index]
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
        replyRevealComplete = false
        imageRevealComplete = true
        responseID = UUID()
        withAnimation(.easeInOut(duration: 0.5)) { phase = .responding }
    }

    /// A hard guarantee for one of the two web rules: if the writer *explicitly*
    /// asks the diary to look something up or search, reach the web even when he
    /// didn't flag it himself. Genuine "I don't know" cases are left entirely to
    /// his own [[WEB]] judgment — we do NOT web-search on incidental words like
    /// "today", "price", or "won" that merely appear in ordinary writing.
    private func freshTraceQuery(from text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let commands = [
            "look up", "look it up", "look this up", "look online", "look up online",
            "search for", "search the web", "search online", "google",
            "find out", "can you find", "look that up",
        ]

        guard commands.contains(where: { lowered.contains($0) }) else { return nil }
        return String(trimmed.prefix(180))
    }

    /// A hard guarantee: if the writer plainly asks for a drawing ("draw a…",
    /// "sketch me…", "a picture of…"), pull the subject out and conjure it even
    /// when the diary failed to tag it. \b avoids matching "withdraw" etc.
    private func forcedSketchSubject(from text: String?) -> String? {
        guard settings.drawingEnabled, let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            "(?i)\\b(?:draw|sketch|paint|illustrate|doodle)\\b(?:\\s+me)?(?:\\s+(?:a|an|the|some))?\\s+(.+)",
            "(?i)\\b(?:picture|drawing|image|illustration)\\s+of\\s+(.+)",
        ]
        let ns = trimmed as NSString
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = re.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                let subject = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-\"'“”‘’"))
                if !subject.isEmpty { return subject }
            }
        }
        return nil
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

/// The page *stirring* while the diary reads in silence — a soft bloom of ink
/// welling up from beneath the paper, breathing where the reply will form. Not a
/// spinner: just enough life that the wait never feels like nothing happened.
private struct PageStir: View {
    @State private var welling = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.ink.opacity(0.16), Theme.ink.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: Theme.isPad ? 78 : 52
                    )
                )
                .frame(width: Theme.isPad ? 168 : 112, height: Theme.isPad ? 168 : 112)
                .scaleEffect(welling ? 1.0 : 0.5)
                .opacity(welling ? 0.9 : 0.3)
                .blur(radius: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                welling = true
            }
        }
    }
}

private struct InkBloomImage: View {
    let image: UIImage
    let progress: Double

    // The image is already inked onto the page's own cream by InkImage, so it is
    // drawn OPAQUE with a plain ink-rising fade — no mask, no white overlay, no
    // blobs. The cream matches the page, so it simply surfaces from the paper.
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .opacity(progress)
            .blur(radius: (1 - progress) * 3)
            .scaleEffect(0.99 + progress * 0.01)
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
