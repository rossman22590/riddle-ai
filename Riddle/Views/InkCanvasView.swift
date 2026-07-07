import SwiftUI
import PencilKit
import UIKit

private let diaryInkWidth: CGFloat = 6

enum PageRitual {
    case guide
    case erase
    case sleep
    case memory
}

/// Bridges the PencilKit canvas to SwiftUI, and exposes snapshot/clear so the
/// diary can "drink" the ink.
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    private var inkColor: UIColor = .black

    var isEmpty: Bool { canvas?.drawing.strokes.isEmpty ?? true }

    var inkBounds: CGRect? {
        guard let bounds = canvas?.drawing.bounds, !bounds.isNull, !bounds.isEmpty else { return nil }
        return bounds
    }

    /// A rendered image of the current ink (nil if the page is blank).
    func snapshot() -> UIImage? {
        guard let canvas, !canvas.drawing.strokes.isEmpty else { return nil }
        let bounds = canvas.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        return canvas.drawing.image(from: bounds, scale: UIScreen.main.scale)
    }

    func clear() {
        canvas?.drawing = PKDrawing()
        applyInkTool()
    }

    func attach(to canvas: PKCanvasView, inkColor: UIColor) {
        self.canvas = canvas
        self.inkColor = inkColor
        applyInkTool()
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
    }

    func updateInkColor(_ color: UIColor, canvas: PKCanvasView) {
        self.canvas = canvas
        guard !inkColor.isEqual(color) else { return }
        inkColor = color
        applyInkTool()
    }

    private var inkTool: PKInkingTool {
        PKInkingTool(.pen, color: inkColor, width: diaryInkWidth)
    }

    private func applyInkTool() {
        guard let canvas else { return }
        canvas.tool = inkTool
    }

    func detectedRitual() -> PageRitual? {
        if looksLikeQuestionMark() { return .guide }
        if looksLikeEraseMark() { return .erase }
        if looksLikeSleepMark() { return .sleep }
        if looksLikeMemoryMark() { return .memory }
        return nil
    }

    /// Local ritual: a lone, oversized question mark summons the guide without
    /// asking the oracle. The check is deliberately forgiving; a false positive
    /// only opens help.
    func looksLikeQuestionMark() -> Bool {
        let pointStrokes = pointStrokes()
        guard !pointStrokes.isEmpty, pointStrokes.count <= 3 else { return false }

        let mainIndex = pointStrokes.indices.max { pointStrokes[$0].count < pointStrokes[$1].count } ?? 0
        let main = pointStrokes[mainIndex]
        guard main.count >= 12 else { return false }

        let mainBounds = bounds(of: main)
        let width = mainBounds.width
        let height = mainBounds.height
        guard height > 180, width > 45, height > width else { return false }

        for (index, stroke) in pointStrokes.enumerated() where index != mainIndex {
            let dot = bounds(of: stroke)
            guard max(dot.width, dot.height) <= 70 else { return false }
            guard dot.midY >= mainBounds.minY + height * 0.58 else { return false }
            guard dot.midX >= mainBounds.minX - 60, dot.midX <= mainBounds.maxX + 60 else { return false }
        }

        var points = main
        if let first = points.first, let last = points.last, first.y > last.y {
            points.reverse()
        }
        guard let start = points.first, let end = points.last else { return false }
        guard start.y <= mainBounds.minY + height * 0.42 else { return false }
        guard end.y >= mainBounds.minY + height * 0.55 else { return false }

        var topMinX = CGFloat.greatestFiniteMagnitude
        var topMaxX = -CGFloat.greatestFiniteMagnitude
        var topMaxY: CGFloat = 0
        for point in points where point.y <= mainBounds.minY + height * 0.48 {
            topMinX = min(topMinX, point.x)
            if point.x > topMaxX {
                topMaxX = point.x
                topMaxY = point.y
            }
        }
        guard topMaxX.isFinite, topMaxX - topMinX >= width * 0.5 else { return false }
        guard topMaxY >= mainBounds.minY + height * 0.06 else { return false }

        let lowerPoints = points.filter { $0.y >= mainBounds.minY + height * 0.66 }
        if !lowerPoints.isEmpty {
            let lower = bounds(of: lowerPoints)
            guard lower.width <= width * 0.62 else { return false }
        }

        return true
    }

    /// A large two-stroke X wipes the page. It must be oversized and alone so
    /// ordinary crossed letters do not become commands.
    private func looksLikeEraseMark() -> Bool {
        let strokes = pointStrokes()
        guard strokes.count == 2 else { return false }

        let all = strokes.flatMap { $0 }
        let whole = bounds(of: all)
        guard whole.width > 150, whole.height > 150 else { return false }
        guard whole.width / whole.height > 0.45, whole.width / whole.height < 2.2 else { return false }

        var slopes = Set<Int>()
        for stroke in strokes {
            let b = bounds(of: stroke)
            guard b.width > whole.width * 0.5, b.height > whole.height * 0.5 else { return false }
            guard let first = stroke.first, let last = stroke.last else { return false }
            let dx = last.x - first.x
            let dy = last.y - first.y
            guard abs(dx) > b.width * 0.55, abs(dy) > b.height * 0.55 else { return false }
            slopes.insert(dx * dy >= 0 ? 1 : -1)
        }

        return slopes.count == 2
    }

    /// A big Z puts the diary to sleep. It is intentionally stricter than help
    /// because sleep should never trigger from normal handwriting.
    private func looksLikeSleepMark() -> Bool {
        let strokes = pointStrokes()
        guard strokes.count == 1, let points = strokes.first, points.count >= 18 else { return false }

        let b = bounds(of: points)
        guard b.width > 150, b.height > 90, b.width > b.height * 1.05 else { return false }
        guard let first = points.first, let last = points.last else { return false }
        guard first.x < b.midX, first.y < b.minY + b.height * 0.38 else { return false }
        guard last.x > b.midX, last.y > b.minY + b.height * 0.62 else { return false }

        let third = points.count / 3
        let top = Array(points.prefix(third))
        let middle = Array(points.dropFirst(third).prefix(third))
        let bottom = Array(points.suffix(points.count - third * 2))
        let topBounds = bounds(of: top)
        let middleBounds = bounds(of: middle)
        let bottomBounds = bounds(of: bottom)

        guard topBounds.width > b.width * 0.35, topBounds.height < b.height * 0.36 else { return false }
        guard topBounds.midY < b.minY + b.height * 0.38 else { return false }
        guard middleBounds.width > b.width * 0.32, middleBounds.height > b.height * 0.34 else { return false }
        guard bottomBounds.width > b.width * 0.35, bottomBounds.height < b.height * 0.36 else { return false }
        guard bottomBounds.midY > b.minY + b.height * 0.62 else { return false }

        return true
    }

    /// A large V opens memory — matching the seal on the diary's cover. One
    /// stroke: down from the upper-left to a point near the bottom-centre, then
    /// back up to the upper-right. Oversized and alone so an ordinary letter
    /// "v" or a small checkmark never becomes a command.
    private func looksLikeMemoryMark() -> Bool {
        let strokes = pointStrokes()
        guard strokes.count == 1, let points = strokes.first, points.count >= 10 else { return false }

        let b = bounds(of: points)
        guard b.width > 130, b.height > 130 else { return false }
        let ratio = b.width / b.height
        guard ratio > 0.5, ratio < 2.2 else { return false }

        guard let first = points.first, let last = points.last else { return false }
        // Both arms open at the top…
        guard first.y < b.minY + b.height * 0.38, last.y < b.minY + b.height * 0.38 else { return false }
        // …starting left, ending right.
        guard first.x < b.midX, last.x > b.midX else { return false }

        // The vertex is the lowest point: near the bottom and near the centre.
        guard let vertex = points.max(by: { $0.y < $1.y }) else { return false }
        guard vertex.y > b.minY + b.height * 0.68 else { return false }
        guard abs(vertex.x - b.midX) < b.width * 0.32 else { return false }

        // The vertex should fall in the middle of the stroke — down, then up.
        guard let vIndex = points.firstIndex(of: vertex) else { return false }
        let n = points.count
        guard vIndex > n / 6, vIndex < n * 5 / 6 else { return false }

        return true
    }

    private func pointStrokes(minPoints: Int = 5) -> [[CGPoint]] {
        guard let strokes = canvas?.drawing.strokes else { return [] }
        return strokes
            .map { stroke in stroke.path.map(\.location) }
            .filter { $0.count >= minPoints }
    }

    private func bounds(of points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

struct InkCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var inkColor: UIColor
    var onChange: () -> Void
    var onPageTap: () -> Void
    /// Fired by a two-finger tap — a discreet way to summon the guide, matching
    /// the original's gesture-only interface (no on-screen chrome).
    var onGuideTap: () -> Void
    var onSleepGesture: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false               // a fixed page, not a scroll view
        canvas.drawingPolicy = .anyInput             // Pencil, finger, or trackpad
        controller.attach(to: canvas, inkColor: inkColor)
        canvas.delegate = context.coordinator

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        let pageTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePageTap)
        )
        pageTap.numberOfTouchesRequired = 1
        pageTap.cancelsTouchesInView = false
        pageTap.delegate = context.coordinator
        canvas.addGestureRecognizer(pageTap)

        let guideTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleGuideTap)
        )
        guideTap.numberOfTouchesRequired = 2
        guideTap.cancelsTouchesInView = false
        guideTap.delegate = context.coordinator
        canvas.addGestureRecognizer(guideTap)

        let sleepPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSleepPress)
        )
        sleepPress.minimumPressDuration = 1.15
        sleepPress.cancelsTouchesInView = false
        sleepPress.delegate = context.coordinator
        canvas.addGestureRecognizer(sleepPress)

        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        controller.updateInkColor(inkColor, canvas: canvas)
        controller.canvas = canvas
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            onChange: onChange,
            onPageTap: onPageTap,
            onGuideTap: onGuideTap,
            onSleepGesture: onSleepGesture
        )
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        let controller: CanvasController
        let onChange: () -> Void
        let onPageTap: () -> Void
        let onGuideTap: () -> Void
        let onSleepGesture: () -> Void

        init(
            controller: CanvasController,
            onChange: @escaping () -> Void,
            onPageTap: @escaping () -> Void,
            onGuideTap: @escaping () -> Void,
            onSleepGesture: @escaping () -> Void
        ) {
            self.controller = controller
            self.onChange = onChange
            self.onPageTap = onPageTap
            self.onGuideTap = onGuideTap
            self.onSleepGesture = onSleepGesture
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange()
        }

        @objc func handlePageTap() {
            onPageTap()
        }

        @objc func handleGuideTap() {
            onGuideTap()
        }

        @objc func handleSleepPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onSleepGesture()
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
