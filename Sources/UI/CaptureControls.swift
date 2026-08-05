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
    /// Bright objects currently in frame (from the sky engine), shown as chips.
    var inFrame: [String] = []

    @State private var timerSeconds = 0        // self-timer: 0 / 3 / 10
    @State private var countdown: Int?         // live countdown display

    // Tripod-steady → a deep stack sized to this device's exposure ceiling;
    // hand-held → one shot. Depth comes from the detected profile.
    private var stackCount: Int {
        guard motion.isSteady else { return 1 }
        return profile?.suggestedStackFrames ?? 24
    }

    var body: some View {
        VStack(spacing: 12) {
            if !inFrame.isEmpty {
                inFrameChips
            }
            if let p = profile {
                Text(p.summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                Text(p.apertureNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if let advice, !advice.isEmpty {
                Label(advice, systemImage: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            levelIndicator
            stabilityChip
            statusLine
            HStack(spacing: 22) {
                timerButton
                shutter
                Color.clear.frame(width: 44, height: 44)   // balance the row
            }
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
            triggerCapture()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(.white).frame(width: 62, height: 62)
                if let c = countdown {
                    Text("\(c)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                } else if stackCount > 1 {
                    Text("\(stackCount)×")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
        }
        .disabled(isBusy || countdown != nil)
        .opacity(isBusy ? 0.5 : 1)
    }

    /// Fire now, or run the self-timer countdown first.
    private func triggerCapture() {
        night.inFrameAnnotation = inFrame
        guard timerSeconds > 0 else {
            night.capture(stackFrames: stackCount); return
        }
        countdown = timerSeconds
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            guard let c = countdown else { t.invalidate(); return }
            if c <= 1 {
                t.invalidate()
                countdown = nil
                night.capture(stackFrames: stackCount)
            } else {
                countdown = c - 1
            }
        }
    }

    // MARK: - In-frame subject chips

    private var inFrameChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(inFrame.prefix(6), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Tripod level indicator

    /// A small bubble level from device roll — helps square the horizon on a
    /// tripod. Turns green when close to level.
    private var levelIndicator: some View {
        let roll = motion.rollDegrees
        let level = abs(roll) < 2
        return HStack(spacing: 8) {
            Image(systemName: "level")
                .font(.system(size: 12))
            ZStack {
                Capsule().fill(.white.opacity(0.15)).frame(width: 90, height: 4)
                Circle()
                    .fill(level ? Color.green : .white)
                    .frame(width: 8, height: 8)
                    .offset(x: max(-42, min(42, CGFloat(roll) * 2)))
            }
        }
        .foregroundStyle(level ? .green : .white.opacity(0.6))
    }

    // MARK: - Self-timer

    private var timerButton: some View {
        Button {
            timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: timerSeconds == 0 ? "timer" : "timer.circle.fill")
                    .font(.system(size: 20))
                Text(timerSeconds == 0 ? "Off" : "\(timerSeconds)s")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(timerSeconds == 0 ? .white.opacity(0.6) : .cyan)
            .frame(width: 44, height: 44)
        }
        .disabled(isBusy)
    }

    private var isBusy: Bool {
        switch night.state {
        case .capturing, .processing: return true
        default: return false
        }
    }
}
