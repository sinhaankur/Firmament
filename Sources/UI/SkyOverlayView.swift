import SwiftUI

/// Draws celestial labels over the camera feed, positioned by the live
/// projection. Tapping a label selects it for the info card.
///
/// Runs on a display-linked timer so labels track the phone as you sweep it.
struct SkyOverlayView: View {
    @ObservedObject var model: SkyViewModel
    @Binding var selected: SkyObject?
    /// Draw constellation stick-figures between the catalog stars.
    var showConstellations: Bool = true

    /// Vertical FOV is derived from horizontal FOV and the view's aspect ratio.
    let horizontalFovDegrees: Double

    var body: some View {
        GeometryReader { geo in
            let vFov = horizontalFovDegrees * Double(geo.size.height / max(geo.size.width, 1))
            let placedItems = placed(in: geo.size, vFov: vFov)
            ZStack {
                if showConstellations {
                    constellationLines(placedItems)
                }
                ForEach(placedItems, id: \.object.id) { item in
                    label(for: item.object)
                        .position(item.point)
                        .onTapGesture { selected = item.object }
                }
            }
            // Re-render frequently so positions follow the gyro.
            .animation(.linear(duration: 0.1), value: model.motion.pointingAzimuth)
        }
        .allowsHitTesting(true)
    }

    /// Draw each constellation figure as connected line segments between the
    /// on-screen positions of its stars. Only segments where both endpoints are
    /// currently on screen are drawn.
    private func constellationLines(_ items: [Placed]) -> some View {
        // Fast lookup: star name → screen point.
        var pointByName: [String: CGPoint] = [:]
        for item in items where item.object.kind == .star {
            pointByName[item.object.name] = item.point
        }
        return Canvas { ctx, _ in
            for figure in Constellations.all {
                var path = Path()
                var pen = false
                for name in figure.path {
                    guard let pt = pointByName[name] else { pen = false; continue }
                    if pen { path.addLine(to: pt) } else { path.move(to: pt); pen = true }
                }
                ctx.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Placed { let object: SkyObject; let point: CGPoint }

    private func placed(in size: CGSize, vFov: Double) -> [Placed] {
        let p = model.pointing
        return model.objects.compactMap { obj -> Placed? in
            // Only label things that are up (with a little slack near horizon).
            guard obj.altitude > -3 else { return nil }
            guard let norm = SkyProjection.project(
                objectAz: obj.azimuth, objectAlt: obj.altitude,
                pointing: p,
                hFovDeg: horizontalFovDegrees, vFovDeg: vFov
            ) else { return nil }
            let point = CGPoint(x: norm.x * size.width, y: norm.y * size.height)
            return Placed(object: obj, point: point)
        }
    }

    @ViewBuilder
    private func label(for obj: SkyObject) -> some View {
        let dimmed = !obj.isAboveHorizon
        HStack(spacing: 6) {
            marker(for: obj)
            Text(obj.name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(dimmed ? 0.35 : 0.95))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(dimmed ? 0.15 : 0.35), in: Capsule())
        .opacity(dimmed ? 0.5 : 1)
    }

    @ViewBuilder
    private func marker(for obj: SkyObject) -> some View {
        switch obj.kind {
        case .sun:
            Circle().fill(.yellow).frame(width: 10, height: 10)
        case .moon:
            Circle().fill(.white.opacity(0.9)).frame(width: 9, height: 9)
        case .planet:
            Circle().fill(.orange).frame(width: 7, height: 7)
        case .star:
            let size = markerSize(mag: obj.magnitude)
            Circle().fill(.white).frame(width: size, height: size)
        case .satellite:
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 10)).foregroundStyle(.cyan)
        }
    }

    private func markerSize(mag: Double?) -> CGFloat {
        guard let m = mag else { return 4 }
        // Brighter (lower mag) → bigger dot, clamped.
        return max(2.5, min(7, 6 - CGFloat(m)))
    }
}
