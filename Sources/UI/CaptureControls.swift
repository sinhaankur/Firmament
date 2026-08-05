import SwiftUI

/// The Snapchat-clean capture surface: one big shutter, a stability chip, and a
/// press-and-hold for a longer stack. The app picks the ceiling; the user just
/// taps.
struct CaptureControls: View {
    @ObservedObject var night: NightCapture
    @ObservedObject var motion: MotionService
    /// The camera engine, for the zoom control.
    @ObservedObject var camera: CameraEngine
    /// The active camera's honest capabilities (drives stack depth + summary).
    var profile: DeviceCaptureProfile?
    /// Optional one-line advice from the capture advisor.
    var advice: String?
    /// Bright objects currently in frame (from the sky engine), shown as chips.
    var inFrame: [String] = []

    @State private var timerSeconds = 0        // self-timer: 0 / 3 / 10
    @State private var countdown: Int?         // live countdown display
    /// Target total integration time (seconds). "Auto" = 0 → use the profile's
    /// suggested depth. Otherwise total exposure is achieved by stacking frames,
    /// which is how we get well past the ~1s single-frame hardware ceiling.
    @State private var totalExposure: Double = 0
    private let exposureSteps: [Double] = [0, 5, 10, 20, 30, 60, 120, 240]

    /// Per-frame exposure the hardware honestly allows (seconds).
    private var perFrame: Double { max(0.1, min(1.0, profile?.maxExposureSeconds ?? 1.0)) }

    // Frames to stack. Auto → profile suggestion (tripod) or 1 (handheld).
    // A chosen total exposure → total / per-frame, capped for sanity.
    private var stackCount: Int {
        if totalExposure > 0 {
            return max(1, min(600, Int((totalExposure / perFrame).rounded())))
        }
        guard motion.isSteady else { return 1 }
        return profile?.suggestedStackFrames ?? 24
    }

    /// The effective total integration time for the current setting.
    private var effectiveTotalSeconds: Double {
        totalExposure > 0 ? totalExposure : Double(stackCount) * perFrame
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
            zoomPicker
            exposurePicker
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

    // MARK: - Zoom picker

    /// Zoom presets. Optical stops keep quality; higher is digital crop (noisy on
    /// faint sky, but fine for the bright Moon/planets — the UI says which).
    private var zoomPicker: some View {
        let stops: [CGFloat] = [1, 2, 3, 5]
        let digital = !camera.isOpticalZoom && camera.zoomFactor > 1.01
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(stops.filter { $0 <= camera.maxAllowedZoom }, id: \.self) { z in
                    zoomButton(z)
                }
            }
            if digital {
                Text("Digital zoom — great for the Moon & planets, but it crops the sensor (noisier on faint stars).")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if camera.zoomFactor > 1.01 {
                Text("Optical zoom — no quality loss.")
                    .font(.system(size: 9)).foregroundStyle(.green.opacity(0.8))
            }
        }
    }

    // MARK: - Total-exposure picker

    /// Choose the total light-integration time. Beyond ~1s it's achieved by
    /// stacking many frames — the honest way past the single-exposure cap, and
    /// how the sky gets genuinely brighter (√N less noise).
    private var exposurePicker: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(exposureSteps, id: \.self) { s in
                        Button {
                            totalExposure = s
                        } label: {
                            Text(s == 0 ? "Auto" : label(for: s))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(totalExposure == s ? Color.white : Color.white.opacity(0.1),
                                            in: Capsule())
                                .foregroundStyle(totalExposure == s ? .black : .white)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            Text(String(format: "≈ %@ total · %d frames × %.1fs",
                        label(for: effectiveTotalSeconds), stackCount, perFrame))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func label(for s: Double) -> String {
        s >= 60 ? String(format: "%.0fm", s / 60) : String(format: "%.0fs", s)
    }

    private func zoomButton(_ z: CGFloat) -> some View {
        let selected = abs(camera.zoomFactor - z) < 0.05
        return Button {
            camera.setZoom(z)
        } label: {
            Text("\(Int(z))×")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(selected ? Color.white : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        }
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
