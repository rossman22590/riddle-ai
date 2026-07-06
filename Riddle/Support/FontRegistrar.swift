import CoreText
import Foundation

/// Registers the bundled Dancing Script font (the diary's hand) at launch so it
/// is available to `Font.custom(...)` without an Info.plist `UIAppFonts` entry.
enum FontRegistrar {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        for name in ["DancingScript"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
