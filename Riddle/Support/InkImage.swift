import UIKit
import CoreImage

/// Forces any generated image into black ink on the app's own cream page colour,
/// with every edge feathered out to that same cream. Drawn opaque, it sits flush
/// on the page — no white flash, no border, no card, no mismatched background.
enum InkImage {
    private static let context = CIContext(options: nil)

    static func inkify(_ data: Data) -> UIImage? {
        guard let input = CIImage(data: data) else { return nil }

        let mono = input.applyingFilter("CIPhotoEffectNoir")
        let inked = mono.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.75,
            kCIInputBrightnessKey: 0.10,
        ])

        guard let cgImage = context.createCGImage(inked, from: inked.extent) else { return nil }
        let source = UIImage(cgImage: cgImage)
        let w = source.size.width
        let h = source.size.height
        guard w > 1, h > 1 else { return source }

        let renderer = UIGraphicsImageRenderer(size: source.size)
        return renderer.image { rctx in
            let ctx = rctx.cgContext
            let bounds = CGRect(origin: .zero, size: source.size)

            // The page's own cream; multiply the ink onto it so any near-white the
            // model produced collapses straight into the paper colour.
            Theme.uiPaper.setFill()
            rctx.fill(bounds)
            let trim = min(w, h) * 0.05
            source.draw(in: bounds.insetBy(dx: -trim, dy: -trim), blendMode: .multiply, alpha: 1)

            // Feather all four edges to the page colour — dissolves any frame the
            // model sneaks in, so the drawing has no boundary at all.
            let margin = min(w, h) * 0.11
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [Theme.uiPaper.cgColor, Theme.uiPaper.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { return }

            func feather(_ clip: CGRect, from: CGPoint, to: CGPoint) {
                ctx.saveGState()
                ctx.clip(to: clip)
                ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
                ctx.restoreGState()
            }
            feather(CGRect(x: 0, y: 0, width: w, height: margin),
                    from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: margin))
            feather(CGRect(x: 0, y: h - margin, width: w, height: margin),
                    from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h - margin))
            feather(CGRect(x: 0, y: 0, width: margin, height: h),
                    from: CGPoint(x: 0, y: 0), to: CGPoint(x: margin, y: 0))
            feather(CGRect(x: w - margin, y: 0, width: margin, height: h),
                    from: CGPoint(x: w, y: 0), to: CGPoint(x: w - margin, y: 0))
        }
    }
}
