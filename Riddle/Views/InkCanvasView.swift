import SwiftUI
import PencilKit

/// Bridges the PencilKit canvas to SwiftUI, and exposes snapshot/clear so the
/// diary can "drink" the ink.
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

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

    func clear() { canvas?.drawing = PKDrawing() }

    /// Local ritual: a lone, oversized question mark summons the guide without
    /// asking the oracle. The check is deliberately forgiving; a false positive
    /// only opens help.
    func looksLikeQuestionMark() -> Bool {
        guard let strokes = canvas?.drawing.strokes else { return false }
        let pointStrokes = strokes
            .map { stroke in stroke.path.map(\.location) }
            .filter { $0.count > 4 }
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

    private func bounds(of points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
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
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        canvas.delegate = context.coordinator

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
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        controller.canvas = canvas
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onPageTap: onPageTap, onGuideTap: onGuideTap, onSleepGesture: onSleepGesture)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        let onChange: () -> Void
        let onPageTap: () -> Void
        let onGuideTap: () -> Void
        let onSleepGesture: () -> Void

        init(
            onChange: @escaping () -> Void,
            onPageTap: @escaping () -> Void,
            onGuideTap: @escaping () -> Void,
            onSleepGesture: @escaping () -> Void
        ) {
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
