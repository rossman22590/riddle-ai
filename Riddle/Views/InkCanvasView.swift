import SwiftUI
import PencilKit

/// Bridges the PencilKit canvas to SwiftUI, and exposes snapshot/clear so the
/// diary can "drink" the ink.
final class CanvasController: ObservableObject {
    weak var canvas: PKCanvasView?

    var isEmpty: Bool { canvas?.drawing.strokes.isEmpty ?? true }

    /// A rendered image of the current ink (nil if the page is blank).
    func snapshot() -> UIImage? {
        guard let canvas, !canvas.drawing.strokes.isEmpty else { return nil }
        let bounds = canvas.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        return canvas.drawing.image(from: bounds, scale: UIScreen.main.scale)
    }

    func clear() { canvas?.drawing = PKDrawing() }
}

struct InkCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var inkColor: UIColor
    var onChange: () -> Void
    /// Fired by a two-finger tap — a discreet way to summon the guide, matching
    /// the original's gesture-only interface (no on-screen chrome).
    var onGuideTap: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false               // a fixed page, not a scroll view
        canvas.drawingPolicy = .anyInput             // Pencil, finger, or trackpad
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        canvas.delegate = context.coordinator

        let guideTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleGuideTap)
        )
        guideTap.numberOfTouchesRequired = 2
        canvas.addGestureRecognizer(guideTap)

        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        controller.canvas = canvas
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onGuideTap: onGuideTap)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onChange: () -> Void
        let onGuideTap: () -> Void

        init(onChange: @escaping () -> Void, onGuideTap: @escaping () -> Void) {
            self.onChange = onChange
            self.onGuideTap = onGuideTap
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange()
        }

        @objc func handleGuideTap() {
            onGuideTap()
        }
    }
}
