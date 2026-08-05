import SwiftUI

/// A rule-of-thirds composition grid + a subtle center mark, for framing in
/// Pure Photography mode. Thin, low-opacity lines that guide without dominating.
///
/// © Ankur Sinha.
struct CompositionGrid: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // Two vertical thirds.
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                }
                // Two horizontal thirds.
                for i in 1...2 {
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
