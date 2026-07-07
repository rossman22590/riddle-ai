import SwiftUI
import UIKit

/// The closed diary, filling the whole screen — dark tooled leather, an embossed
/// gold name, stitched frame, and a wax seal. It greets every opening; a touch
/// melts it away to the page beneath (no gimmicky hinge, just the cover lifting).
struct DiaryGate: View {
    var onOpen: () -> Void

    @State private var leaving = false
    @State private var breathe = false

    private let leatherHi = Color(red: 0.21, green: 0.12, blue: 0.11)
    private let leatherLo = Color(red: 0.065, green: 0.042, blue: 0.040)
    private let gold = Color(red: 0.72, green: 0.60, blue: 0.38)

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // Leather body — a vertical gradient with a diagonal sheen.
                LinearGradient(colors: [leatherHi, leatherLo], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Pores, mottling and faint scratches — the grain of real hide.
                LeatherGrain()
                    .blendMode(.overlay)

                // A warm light from above, and worn, darkened corners.
                RadialGradient(colors: [.white.opacity(0.10), .clear],
                               center: .init(x: 0.5, y: 0.16), startRadius: 0, endRadius: H * 0.55)
                ForEach(corners(W, H), id: \.self) { pt in
                    RadialGradient(colors: [.black.opacity(0.32), .clear],
                                   center: .center, startRadius: 0, endRadius: min(W, H) * 0.28)
                        .frame(width: min(W, H) * 0.5, height: min(W, H) * 0.5)
                        .position(x: pt.x, y: pt.y)
                }

                // A tooled double frame with a line of gold stitching between.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(gold.opacity(0.5), lineWidth: 1.5)
                    .padding(26)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(gold.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .padding(32)
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(gold.opacity(0.26), lineWidth: 0.8)
                    .padding(38)

                // The embossed name, sunk into the leather near the top.
                VStack(spacing: Theme.isPad ? 14 : 10) {
                    embossed(
                        Text("T. M. RIDDLE")
                            .font(.system(size: Theme.isPad ? 40 : 30, weight: .semibold, design: .serif))
                            .tracking(Theme.isPad ? 10 : 7)
                    )
                    Rectangle().fill(gold.opacity(0.42)).frame(width: W * 0.28, height: 1)
                    embossed(
                        Text("· 1943 ·")
                            .font(.system(size: Theme.isPad ? 18 : 14, design: .serif))
                            .tracking(3)
                    )
                }
                .position(x: W / 2, y: H * 0.30)

                seal(diameter: min(W, H) * (Theme.isPad ? 0.26 : 0.34))
                    .position(x: W / 2, y: H * 0.60)

                // Edge vignette so the cover reads as a solid, lit object.
                RadialGradient(colors: [.clear, .black.opacity(0.5)],
                               center: .center, startRadius: min(W, H) * 0.42, endRadius: max(W, H) * 0.72)
                    .allowsHitTesting(false)
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.06 : 1)          // the cover lifts toward you as it melts away
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private func open() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeInOut(duration: 0.7)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { onOpen() }
    }

    // MARK: - Pieces

    private func embossed(_ text: Text) -> some View {
        text
            .foregroundStyle(gold)
            .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1.5)
            .shadow(color: gold.opacity(0.28), radius: 0.5, x: 0, y: -0.6)
    }

    private func seal(diameter d: CGFloat) -> some View {
        let oxblood = Color(red: 0.46, green: 0.14, blue: 0.13)
        let oxbloodLo = Color(red: 0.27, green: 0.07, blue: 0.07)
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: d + 6, height: d + 6)
                .blur(radius: 9)
                .offset(y: 7)

            // Poured wax, lit from the upper-left.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.58, green: 0.20, blue: 0.17), oxblood, oxbloodLo],
                    center: .init(x: 0.38, y: 0.30), startRadius: 1, endRadius: d * 0.72))
                .frame(width: d, height: d)

            // A raised, rounded rim.
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.4)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: d * 0.055)
                .frame(width: d, height: d)

            Circle()
                .strokeBorder(oxbloodLo.opacity(0.85), lineWidth: 1.5)
                .frame(width: d * 0.72, height: d * 0.72)

            // The serpentine S, pressed into the wax.
            Text("S")
                .font(.custom("DancingScript-Regular", size: d * 0.52))
                .foregroundStyle(oxbloodLo)
                .shadow(color: .white.opacity(0.14), radius: 0.5, x: 0, y: -0.8)
                .shadow(color: .black.opacity(0.5), radius: 0.6, x: 0, y: 1.2)
                .offset(y: -d * 0.02)

            // A soft gloss on the wax.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.22), .clear],
                                     center: .center, startRadius: 0, endRadius: d * 0.22))
                .frame(width: d * 0.5, height: d * 0.34)
                .offset(x: -d * 0.13, y: -d * 0.17)
                .blur(radius: 2)
        }
        .scaleEffect(breathe ? 1.015 : 0.99)      // a faint breath, inviting the touch
    }

    private func corners(_ w: CGFloat, _ h: CGFloat) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)]
    }
}

/// Procedural leather grain — thousands of tiny light/dark specks plus a few
/// faint scratches, seeded so it never shimmers between redraws.
private struct LeatherGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: 0xC0FFEE_1943)
            for _ in 0..<2200 {
                let x = Double.random(in: 0...size.width, using: &rng)
                let y = Double.random(in: 0...size.height, using: &rng)
                let s = Double.random(in: 0.5...2.3, using: &rng)
                let light = Double.random(in: 0...1, using: &rng) > 0.5
                let a = Double.random(in: 0.02...0.08, using: &rng)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                    with: .color((light ? Color.white : Color.black).opacity(a))
                )
            }
            for _ in 0..<14 {
                let x = Double.random(in: 0...size.width, using: &rng)
                let y = Double.random(in: 0...size.height, using: &rng)
                let len = Double.random(in: 20...90, using: &rng)
                let ang = Double.random(in: -0.6...0.6, using: &rng)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len))
                ctx.stroke(path, with: .color(.black.opacity(0.05)), lineWidth: 0.6)
            }
        }
    }
}
