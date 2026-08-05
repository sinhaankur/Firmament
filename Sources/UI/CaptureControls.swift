import SwiftUI

/// The Snapchat-clean capture surface: one big shutter, a stability chip, and a
/// press-and-hold for a longer stack. The app picks the ceiling; the user just
/// taps.
struct CaptureControls: View {
    @ObservedObject var night: NightCapture
    @ObservedObject var motion: MotionService
    /// The active camera's honest capabilities (drives stack depth + summary).
    var profile: DeviceCaptureProfile?
    /// Optional one-line advice from the capture advisor.
    var advice: String?

    // Tripod-steady → a deep stack sized to this device's exposure ceiling;
    // hand-held → one shot. Depth comes from the detected profile.
    private var stackCount: Int {
        guard motion.isSteady else { return 1 }
        return profile?.suggestedStackFrames ?? 24
    }

    var body: some View {
        VStack(spacing: 12) {
            if let p = profile {
                Text(p.summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let advice, !advice.isEmpty {
                Label(advice, systemImage: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            stabilityChip
            statusLine
            shutter
        }
        .padding(.bottom, 8)
    }

    private var stabilityChip: some View {
        Label(
            motion.isSteady ? "Steady — long capture ready" : "Hold still or use a tripod",
            systemImage: motion.isSteady ? "checkmark.circle.fill" : "hand.raised.slash"
        )
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(motion.isSteady ? .green : .yellow)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
    }

    @ViewBuilder
    private var statusLine: some View {
        switch night.state {
        case .capturing(let p):
            Text("Capturing… \(Int(p * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        case .processing:
            Text("Stacking frames…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let m):
            Label(m, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundStyle(.red)
        case .idle:
            Color.clear.frame(height: 14)
        }
    }

    private var shutter: some View {
        Button {
            night.inFrameAnnotation = []
            night.capture(stackFrames: stackCount)
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(.white).frame(width: 62, height: 62)
                if stackCount > 1 {
                    Text("\(stackCount)×")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    private var isBusy: Bool {
        switch night.state {
        case .capturing, .processing: return true
        default: return false
        }
    }
}
