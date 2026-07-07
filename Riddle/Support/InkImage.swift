import UIKit
import CoreImage

/// Forces any generated image into black ink on the app's own cream page colour,
/// cropped to the drawing itself (so it fills the frame instead of floating tiny
/// in empty canvas) and feathered to that same cream at the edges. Drawn opaque,
/// it sits flush on the page — no white flash, no border, no mismatched background.
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

        guard let baseCG = context.createCGImage(inked, from: inked.extent) else { return nil }

        // Trim the empty canvas around the actual ink so the drawing fills the page.
        let cg = crop(baseCG) ?? baseCG
        let source = UIImage(cgImage: cg)
        let w = source.size.width
        let h = source.size.height
        guard w > 1, h > 1 else { return source }

        // A little breathing room so the ink doesn't butt the very edge.
        let pad = min(w, h) * 0.07
        let canvasSize = CGSize(width: w + pad * 2, height: h + pad * 2)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { rctx in
            let ctx = rctx.cgContext
            let bounds = CGRect(origin: .zero, size: canvasSize)

            // The page's own cream; multiply the ink onto it so any near-white the
            // model produced collapses straight into the paper colour.
            Theme.uiPaper.setFill()
            rctx.fill(bounds)
            source.draw(in: CGRect(x: pad, y: pad, width: w, height: h), blendMode: .multiply, alpha: 1)

            // Feather all four edges to the page colour — dissolves any frame the
            // model sneaks in, so the drawing has no boundary at all.
            let margin = pad + min(w, h) * 0.04
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [Theme.uiPaper.cgColor, Theme.uiPaper.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { return }

            let cw = canvasSize.width, ch = canvasSize.height
            func feather(_ clip: CGRect, from: CGPoint, to: CGPoint) {
                ctx.saveGState()
                ctx.clip(to: clip)
                ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
                ctx.restoreGState()
            }
            feather(CGRect(x: 0, y: 0, width: cw, height: margin),
                    from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: margin))
            feather(CGRect(x: 0, y: ch - margin, width: cw, height: margin),
                    from: CGPoint(x: 0, y: ch), to: CGPoint(x: 0, y: ch - margin))
            feather(CGRect(x: 0, y: 0, width: margin, height: ch),
                    from: CGPoint(x: 0, y: 0), to: CGPoint(x: margin, y: 0))
            feather(CGRect(x: cw - margin, y: 0, width: margin, height: ch),
                    from: CGPoint(x: cw, y: 0), to: CGPoint(x: cw - margin, y: 0))
        }
    }

    /// The bounding box of the actual ink (dark pixels), so we can crop away the
    /// empty canvas the model tends to leave around a small drawing.
    private static func crop(_ cg: CGImage) -> CGImage? {
        let width = cg.width
        let height = cg.height
        guard width > 8, height > 8 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let threshold = 175   // luminance below this counts as ink
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let i = row + x * bytesPerPixel
                let lum = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                if lum < threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let contentW = maxX - minX + 1
        let contentH = maxY - minY + 1

        // If the ink already fills most of the canvas, don't bother cropping.
        if contentW > Int(Double(width) * 0.9) && contentH > Int(Double(height) * 0.9) { return nil }
        // Ignore stray specks.
        guard contentW * contentH > 400 else { return nil }

        let rect = CGRect(x: minX, y: minY, width: contentW, height: contentH)
        return cg.cropping(to: rect)
    }
}
