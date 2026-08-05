import SwiftUI

/// Spot mode — find the ISS in the sky. When it's overhead, a large arrow points
/// from where you're aiming toward the station's real alt/az; when it's not up,
/// it shows the next visible pass with a countdown.
///
/// © Ankur Sinha.
struct SpotView: View {
    @ObservedObject var model: SkyViewModel

    var body: some View {
        VStack(spacing: 16) {
            if let iss = model.iss, iss.isAboveHorizon {
                overheadCard(iss)
            } else if let pass = model.nextIssPass {
                nextPassCard(pass)
            } else {
                searchingCard
            }
        }
    }

    // MARK: - ISS is up now

    private func overheadCard(_ iss: SkyObject) -> some View {
        let delta = angleDelta(from: model.motion.pointingAzimuth, to: iss.azimuth)
        let aligned = abs(delta) < 12 && abs(model.motion.pointingAltitude - iss.altitude) < 12

        return VStack(spacing: 12) {
            Text(aligned ? "You're on it — that's the ISS" : "The ISS is up right now")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(aligned ? .green : .white)

            // Guiding arrow: rotate toward the station's azimuth relative to aim.
            Image(systemName: "location.north.fill")
                .font(.system(size: 44))
                .foregroundStyle(aligned ? .green : .cyan)
                .rotationEffect(.degrees(delta))
                .animation(.easeOut(duration: 0.15), value: delta)

            Text(String(format: "Alt %.0f° · Az %.0f° · %@",
                        iss.altitude, iss.azimuth, iss.distanceText ?? ""))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.cyan.opacity(0.3)))
    }

    // MARK: - Next pass

    private func nextPassCard(_ pass: (start: Date, peakAltitude: Double, peakAzimuth: Double)) -> some View {
        VStack(spacing: 8) {
            Text("Next ISS pass")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan)
            Text(pass.start, style: .relative)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(format: "Peaks at %.0f° altitude, toward %@",
                        pass.peakAltitude, compass(pass.peakAzimuth)))
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
            Text("Finding the ISS…")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            Text("No visible pass in the next 24 h from here.")
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
