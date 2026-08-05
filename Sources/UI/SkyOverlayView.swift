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
                // Full naked-eye star field as points (drawn first, behind labels).
                starFieldCanvas(in: geo.size, vFov: vFov)
                if showConstellations {
                    constellationLines(in: geo.size, vFov: vFov)
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

    /// Draw each constellation figure as connected line segments. Projects the
    /// figure's stars directly from the resolved sky objects (independent of the
    /// de-collided label set) so lines are never broken by label capping.
    private func constellationLines(in size: CGSize, vFov: Double) -> some View {
        let p = model.pointing
        // Name → screen point for every resolved star currently up.
        var pointByName: [String: CGPoint] = [:]
        for obj in model.objects where obj.kind == .star && obj.altitude > -3 {
            if let norm = SkyProjection.project(
                objectAz: obj.azimuth, objectAlt: obj.altitude,
                pointing: p, hFovDeg: horizontalFovDegrees, vFovDeg: vFov
            ) {
                pointByName[obj.name] = CGPoint(x: norm.x * size.width, y: norm.y * size.height)
            }
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

    /// Draw the full naked-eye star field as points via a single Canvas — cheap
    /// even at ~8,900 stars because it's one draw pass, not thousands of views.
    /// Brighter stars → bigger, more opaque dots.
    private func starFieldCanvas(in size: CGSize, vFov: Double) -> some View {
        let p = model.pointing
        let field = model.starField
        return Canvas { ctx, _ in
            for star in field {
                guard star.alt > -3 else { continue }
                guard let norm = SkyProjection.project(
                    objectAz: star.az, objectAlt: star.alt, pointing: p,
                    hFovDeg: horizontalFovDegrees, vFovDeg: vFov
                ) else { continue }
                let x = norm.x * size.width, y = norm.y * size.height
                // Size + brightness from magnitude (−1.5…6.5 → big…tiny).
                let m = star.mag
                let radius = max(0.5, min(2.6, 2.3 - m * 0.32))
                let opacity = max(0.18, min(1.0, 1.05 - m * 0.13))
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }

    private struct Placed { let object: SkyObject; let point: CGPoint }

    private func placed(in size: CGSize, vFov: Double) -> [Placed] {
        let p = model.pointing

        // Project the objects worth labeling. Unnamed catalog stars (whose name
        // is a bare "HYG-####" id) are never labeled — they live in the point
        // field. Everything else is a candidate.
        var candidates: [(placed: Placed, priority: Double)] = []
        for obj in model.objects {
            guard obj.altitude > -3 else { continue }
            if obj.kind == .star && obj.name.hasPrefix("HYG-") { continue }
            guard let norm = SkyProjection.project(
                objectAz: obj.azimuth, objectAlt: obj.altitude,
                pointing: p, hFovDeg: horizontalFovDegrees, vFovDeg: vFov
            ) else { continue }
            let point = CGPoint(x: norm.x * size.width, y: norm.y * size.height)
            // Priority: Sun/Moon/planets/satellites first, then brighter stars.
            let kindBoost: Double = obj.kind == .star ? 0 : -100
            let priority = kindBoost + (obj.magnitude ?? 6)
            candidates.append((Placed(object: obj, point: point), priority))
        }

        // De-collide: keep the highest-priority label in any ~72pt neighbourhood
        // so labels never stack into an unreadable wall.
        candidates.sort { $0.priority < $1.priority }
        var kept: [Placed] = []
        let minGap: CGFloat = 72
        for c in candidates {
            let tooClose = kept.contains { existing in
                abs(existing.point.x - c.placed.point.x) < minGap &&
                abs(existing.point.y - c.placed.point.y) < minGap
            }
            if !tooClose { kept.append(c.placed) }
            if kept.count >= 18 { break }   // hard cap keeps it clean
        }
        return kept
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
