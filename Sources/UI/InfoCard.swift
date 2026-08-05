import SwiftUI

/// Slide-up detail for a tapped celestial object. Terse, factual, and honest —
/// shows the alt/az and magnitude that actually drove the label.
struct InfoCard: View {
    let object: SkyObject
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.name)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(object.kind.rawValue.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Divider().overlay(.white.opacity(0.15))

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    row("Altitude", String(format: "%.1f°", object.altitude),
                        note: object.isAboveHorizon ? nil : "below horizon")
                    row("Azimuth", String(format: "%.1f° %@",
                                          object.azimuth, compass(object.azimuth)))
                    if let m = object.magnitude {
                        row("Magnitude", String(format: "%.2f", m))
                    }
                    if let d = object.distanceText {
                        row("Distance", d)
                    }
                }

                if let blurb = object.blurb {
                    Text(blurb)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1)))
            .padding()
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, note: String? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func compass(_ az: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let i = Int((az / 45).rounded()) % 8
        return dirs[i]
    }
}
