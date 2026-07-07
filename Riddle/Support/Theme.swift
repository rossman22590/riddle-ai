import SwiftUI
import UIKit

/// Palette + type for the diary. Matches the reMarkable "Tom Riddle diary" look:
/// a soft e-ink paper page with near-black ink, and replies penned in Dancing
/// Script. Colours are fixed (not derived from the system appearance).
enum Theme {
    /// Soft paper-white of the e-ink page.
    static let paper       = Color(red: 0.957, green: 0.949, blue: 0.929)
    static let paperEdge   = Color(red: 0.905, green: 0.894, blue: 0.866)
    /// E-ink "black" — a deep neutral, not pure #000.
    static let ink         = Color(red: 0.102, green: 0.098, blue: 0.106)
    static let replyInk    = Color(red: 0.102, green: 0.098, blue: 0.106)
    static let accent      = Color(red: 0.102, green: 0.098, blue: 0.106)
    static let faint       = Color(red: 0.102, green: 0.098, blue: 0.106).opacity(0.34)

    static var uiInk: UIColor { UIColor(red: 0.102, green: 0.098, blue: 0.106, alpha: 1) }
    static var uiPaper: UIColor { UIColor(red: 0.957, green: 0.949, blue: 0.929, alpha: 1) }
    static let paperHex = "#F4F2ED"
    static let paperRGB = "RGB(244, 242, 237)"
    static let inkHex = "#1A191B"
    static let inkRGB = "RGB(26, 25, 27)"

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The "hands" the diary can write in. Dancing Script is the authentic one;
    /// the rest are alternates. Values are PostScript font names.
    static let hands: [(label: String, fontName: String)] = [
        ("Dancing Script", "DancingScript-Regular"),
        ("Snell Roundhand", "SnellRoundhand-Bold"),
        ("Savoye",          "SavoyeLetPlain"),
        ("Zapfino",         "Zapfino"),
        ("Bradley Hand",    "BradleyHandITCTTBold"),
    ]

    static func fontName(for hand: String) -> String {
        hands.first { $0.label == hand }?.fontName ?? "DancingScript-Regular"
    }

    /// The cursive font the diary replies in, sized for the current device.
    static func replySize(for hand: String) -> CGFloat {
        let scriptScale: CGFloat = hand == "Dancing Script" ? 1.14 : 1.0
        return (isPad ? 40 : 28) * scriptScale
    }

    static func replyFont(for hand: String) -> Font {
        .custom(fontName(for: hand), size: replySize(for: hand))
    }

    /// The same reply face as a `UIFont` — needed to trace glyph outlines with
    /// Core Text so the diary's hand is drawn stroke by stroke.
    static func replyUIFont(for hand: String) -> UIFont {
        let size = replySize(for: hand)
        return UIFont(name: fontName(for: hand), size: size) ?? .systemFont(ofSize: size)
    }

    /// The display face for the title / marks (also Dancing Script).
    static func display(_ size: CGFloat) -> Font {
        .custom("DancingScript-Regular", size: size)
    }
}
