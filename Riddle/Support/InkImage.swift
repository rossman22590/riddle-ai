import UIKit
import CoreImage

/// Forces any generated image into near-black ink on the same cream paper the
/// app uses. This guarantees no white image canvas even if the model returns
/// one.
enum InkImage {
    private static let context = CIContext(options: nil)

    static func inkify(_ data: Data) -> UIImage? {
        guard let input = CIImage(data: data) else { return nil }

        let mono = input.applyingFilter("CIPhotoEffectNoir")
        let inked = mono.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.7,
            kCIInputBrightnessKey: 0.08,
        ])

        guard let cgImage = context.createCGImage(inked, from: inked.extent) else { return nil }

        let source = UIImage(cgImage: cgImage)
        let renderer = UIGraphicsImageRenderer(size: source.size)
        return renderer.image { context in
            Theme.uiPaper.setFill()
            context.fill(CGRect(origin: .zero, size: source.size))
            source.draw(
                in: CGRect(origin: .zero, size: source.size),
                blendMode: .multiply,
                alpha: 1
            )
        }
    }
}
