import SwiftUI

/// Explore-mode heads-up display: a center reticle that reads out whatever you're
/// pointing at, plus a live compass + altitude strip. It turns "wave the phone
/// around and hope a label lands under your thumb" into "aim, and it tells you."
///
/// © Ankur Sinha.
struct ExploreHUD: View {
    @ObservedObject var model: SkyViewModel
    /// Tapping the reticle readout opens the full InfoCard for that object.
    let onOpen: (SkyObject) -> Void

    var body: some View {
        let target = model.nearestToAim()
        VStack {
            compassStrip
            Spacer()
            reticle(target: target)
            Spacer()
            if let target {
                readout(target)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: target?.id)
        .allowsHitTesting(true)
    }

    // MARK: - Center reticle

    private func reticle(target: SkyObject?) -> some View {
        let locked = target != nil
        return ZStack {
            Circle()
                .stroke((locked ? Color.cyan : .white).opacity(locked ? 0.9 : 0.35),
                        lineWidth: locked ? 2 : 1)
                .frame(width: 54, height: 54)
            // Tick marks.
            ForEach(0..<4) { i in
                Rectangle()
                    .fill((locked ? Color.cyan : .white).opacity(0.6))
                    .frame(width: 1.5, height: 8)
                    .offset(y: -33)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            if !locked {
                Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
            }
        }
        .animation(.easeOut(duration: 0.15), value: locked)
    }

    // MARK: - Readout

    private func readout(_ obj: SkyObject) -> some View {
        Button { onOpen(obj) } label: {
            VStack(spacing: 3) {
                Text(obj.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(obj.kind.rawValue.capitalized)
                    if let m = obj.magnitude { Text(String(format: "mag %.1f", m)) }
                    Text(String(format: "%.0f° up", obj.altitude))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                Text("Tap for details")
                    .font(.system(size: 9)).foregroundStyle(.cyan)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - Compass + altitude strip

    private var compassStrip: some View {
        HStack(spacing: 10) {
            Label(compass(model.motion.pointingAzimuth), systemImage: "safari")
                .labelStyle(.titleAndIcon)
            Text(String(format: "%.0f°", model.motion.pointingAzimuth))
                .foregroundStyle(.white.opacity(0.5))
            Divider().frame(height: 12).overlay(.white.opacity(0.2))
            Image(systemName: model.motion.pointingAltitude >= 0 ? "arrow.up" : "arrow.down")
            Text(String(format: "%.0f°", abs(model.motion.pointingAltitude)))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
        .padding(.top, 4)
    }

    private func compass(_ az: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        return dirs[Int((az / 45).rounded()) % 8]
    }
}
