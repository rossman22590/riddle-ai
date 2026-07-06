import UIKit
import CoreImage

/// Forces any generated image into black-ink-on-white: desaturated and
/// high-contrast, so — combined with a `.multiply` blend onto the page — only
/// the ink strokes show. Guarantees the "always ink style" rule regardless of
/// what the model returns.
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
        return UIImage(cgImage: cgImage)
    }
}
