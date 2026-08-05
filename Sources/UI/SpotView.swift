import SwiftUI

/// Spot mode — find a satellite in the sky with clear, plain-language direction.
/// When one is overhead, it names the closest, points a compass-true arrow at
/// its real alt/az, and tells you which way to turn and tilt ("turn right, look
/// up") until you're on it. When nothing is up, it shows the next visible pass
/// with a countdown and where on the horizon it'll rise.
///
/// © Ankur Sinha.
struct SpotView: View {
    @ObservedObject var model: SkyViewModel

    var body: some View {
        VStack(spacing: 16) {
            if let sat = model.closestSatellite {
                overheadCard(sat)
            } else if let pass = model.nextPass {
                nextPassCard(pass)
            } else {
                searchingCard
            }
        }
    }

    // MARK: - A satellite is up now

    private func overheadCard(_ sat: SatelliteTracker.Fix) -> some View {
        let dAz = angleDelta(from: model.motion.pointingAzimuth, to: sat.azimuth)
        let dAlt = sat.altitude - model.motion.pointingAltitude
        let aligned = abs(dAz) < 10 && abs(dAlt) < 10

        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(aligned ? .green : .cyan).frame(width: 7, height: 7)
                Text(aligned ? "You're on it — \(sat.name)" : "\(sat.name) is up now")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(aligned ? .green : .white)
            }

            // Big compass-true guiding arrow: 0° = straight ahead (where you aim).
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 96, height: 96)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(aligned ? .green : .cyan)
                    .rotationEffect(.degrees(dAz))
                    .animation(.easeOut(duration: 0.15), value: dAz)
            }

            // Plain-language instruction.
            Text(instruction(dAz: dAz, dAlt: dAlt, aligned: aligned))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(aligned ? .green : .white.opacity(0.9))
                .multilineTextAlignment(.center)

            Text(String(format: "Look %@ · %.0f° up · %.0f km away",
                        compass(sat.azimuth), sat.altitude, sat.rangeKm))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke((aligned ? Color.green : .cyan).opacity(0.35)))
    }

    /// Turn-by-turn text from the angular offsets.
    private func instruction(dAz: Double, dAlt: Double, aligned: Bool) -> String {
        if aligned { return "Hold there — that bright moving point is it." }
        var parts: [String] = []
        if abs(dAz) >= 10 {
            parts.append(dAz > 0 ? "turn right" : "turn left")
        }
        if abs(dAlt) >= 10 {
            parts.append(dAlt > 0 ? "look higher" : "look lower")
        }
        if parts.isEmpty { return "Almost there…" }
        // Capitalize the first word.
        let joined = parts.joined(separator: " and ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    // MARK: - Next pass

    private func nextPassCard(_ pass: SatelliteTracker.Pass) -> some View {
        VStack(spacing: 8) {
            Text("Next visible pass")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan)
            Text(pass.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(pass.start, style: .relative)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(format: "Rises toward %@, peaks %.0f° up",
                        compass(pass.peakAzimuth), pass.peakAltitude))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            Text(pass.start, style: .time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.cyan.opacity(0.3)))
    }

    private var searchingCard: some View {
        VStack(spacing: 8) {
            ProgressView().tint(.cyan)
            Text("Scanning for satellites…")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            Text("None visible in the next 24 h from here.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

    private func angleDelta(from: Double, to: Double) -> Double {
        var d = to - from
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private func compass(_ az: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        return dirs[Int((az / 45).rounded()) % 8]
    }
}
