import SwiftUI

/// The Snapchat-clean capture surface: one big shutter, a stability chip, and a
/// press-and-hold for a longer stack. The app picks the ceiling; the user just
/// taps.
struct CaptureControls: View {
    @ObservedObject var night: NightCapture
    @ObservedObject var motion: MotionService
    /// The camera engine, for the zoom control.
    @ObservedObject var camera: CameraEngine
    /// The time-lapse recorder.
    @ObservedObject var timelapse: TimelapseRecorder
    /// The active camera's honest capabilities (drives stack depth + summary).
    var profile: DeviceCaptureProfile?
    /// Optional one-line advice from the capture advisor.
    var advice: String?
    /// Bright objects currently in frame (from the sky engine), shown as chips.
    var inFrame: [String] = []
    /// Focus-peaking toggle (bound to the parent).
    @Binding var peakingOn: Bool
    /// Pure Photography (hide astronomy overlays) + composition grid.
    @Binding var pureMode: Bool
    @Binding var showGrid: Bool

    @State private var timerSeconds = 0        // self-timer: 0 / 3 / 10
    @State private var countdown: Int?         // live countdown display
    @State private var isTimelapse = false     // Photo | Time-lapse
    @State private var manualMode = false       // Auto | Manual exposure
    @State private var manualISO: Float = 1600
    @State private var manualShutter: Double = 1.0   // seconds
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

    @State private var showSettings = false    // expandable pro controls

    var body: some View {
        VStack(spacing: 10) {
            // Pure Photography vs. Sky (astronomy overlay) + grid.
            pureBar

            // One quiet info line — tap to see the advisor + hardware detail.
            infoBar

            // Expandable pro controls (hidden by default for a clean surface).
            if showSettings {
                VStack(spacing: 10) {
                    if let p = profile {
                        Text(p.summary)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    if !inFrame.isEmpty { inFrameChips }
                    zoomPicker
                    if !isTimelapse {
                        manualExposureControls
                        if !manualMode { exposurePicker }
                    }
                    focusControls
                    levelIndicator
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            modeToggle

            if isTimelapse {
                timelapseControls
            } else {
                statusLine
                HStack(spacing: 22) {
                    settingsToggleButton
                    shutter
                    timerButton
                }
            }
        }
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
    }

    // MARK: - Pure Photography / Sky toggle + grid

    private var pureBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach([("Sky", false), ("Pure", true)], id: \.0) { title, pure in
                    Button { pureMode = pure } label: {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(pureMode == pure ? Color.white : Color.clear, in: Capsule())
                            .foregroundStyle(pureMode == pure ? .black : .white)
                    }
                }
            }
            .padding(3)
            .background(.black.opacity(0.4), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15)))

            // Grid toggle.
            Button { showGrid.toggle() } label: {
                Image(systemName: showGrid ? "grid.circle.fill" : "grid.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(showGrid ? .cyan : .white.opacity(0.6))
            }
        }
    }

    // MARK: - Info bar (advisor + steadiness in one quiet line)

    private var infoBar: some View {
        Button { showSettings.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: motion.isSteady ? "checkmark.circle.fill" : "hand.raised.slash")
                    .foregroundStyle(motion.isSteady ? .green : .yellow)
                Text(infoText)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: showSettings ? "chevron.down" : "slider.horizontal.3")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var infoText: String {
        if let advice, !advice.isEmpty { return advice }
        return motion.isSteady ? "Steady — ready for a long capture" : "Hold still or use a tripod"
    }

    private var settingsToggleButton: some View {
        Button { showSettings.toggle() } label: {
            VStack(spacing: 1) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 20))
                Text("Settings").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(showSettings ? .cyan : .white.opacity(0.6))
            .frame(width: 44, height: 44)
        }
    }

    // MARK: - Photo | Time-lapse toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach([("Photo", false), ("Time-lapse", true)], id: \.0) { title, tl in
                Button { isTimelapse = tl } label: {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isTimelapse == tl ? Color.white : Color.clear, in: Capsule())
                        .foregroundStyle(isTimelapse == tl ? .black : .white)
                }
            }
        }
        .padding(3)
        .frame(maxWidth: 220)
        .background(.black.opacity(0.4), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15)))
    }

    // MARK: - Time-lapse controls

    @ViewBuilder
    private var timelapseControls: some View {
        VStack(spacing: 10) {
            // Interval + frame count steppers.
            HStack(spacing: 14) {
                stepper("Every", "\(Int(timelapse.interval))s") {
                    timelapse.interval = max(1, timelapse.interval - 1)
                } up: {
                    timelapse.interval = min(30, timelapse.interval + 1)
                }
                stepper("Frames", "\(timelapse.frameCount)") {
                    timelapse.frameCount = max(10, timelapse.frameCount - 30)
                } up: {
                    timelapse.frameCount = min(1200, timelapse.frameCount + 30)
                }
            }
            Text("Shoot ≈ \(timelapse.estimatedDurationText) · \(timelapse.frameCount) frames → \(Int(Double(timelapse.frameCount) / Double(timelapse.outputFPS)))s video")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            timelapseStatus

            // Record / stop button.
            Button {
                if timelapse.isRecording { timelapse.cancel() } else { timelapse.start() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                    if timelapse.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timelapseStatus: some View {
        switch timelapse.state {
        case .recording(let done, let total):
            Text("Recording \(done)/\(total)…")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
        case .assembling:
            Text("Assembling video…")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
        case .saved:
            Label("Time-lapse saved", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let m):
            Label(m, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red)
        case .idle:
            Color.clear.frame(height: 14)
        }
    }

    private func stepper(_ label: String, _ value: String, _ down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 10) {
                Button(action: down) { Image(systemName: "minus.circle") }
                Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(minWidth: 44)
                Button(action: up) { Image(systemName: "plus.circle") }
            }
            .foregroundStyle(.white)
            .disabled(timelapse.isRecording)
        }
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

    // MARK: - Focus (manual focus + peaking)

    @State private var manualFocusMode = false

    @ViewBuilder
    private var focusControls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Focus").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Toggle("Peaking", isOn: $peakingOn)
                    .labelsHidden()
                Text("Peaking").font(.system(size: 10)).foregroundStyle(peakingOn ? .pink : .white.opacity(0.5))
                Spacer()
                Button(manualFocusMode ? "Auto" : "Manual") {
                    manualFocusMode.toggle()
                    if manualFocusMode { camera.manualFocus = true; camera.setManualFocus(camera.lensPosition) }
                    else { camera.manualFocus = false; camera.setAutoFocus() }
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
            }
            if manualFocusMode {
                HStack(spacing: 8) {
                    Image(systemName: "mountain.2").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Slider(value: Binding(
                        get: { camera.lensPosition },
                        set: { camera.setManualFocus($0) }), in: 0...1)
                        .tint(.cyan)
                    Text("∞").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                Text("For stars, slide toward ∞ and use Peaking to confirm sharp points.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Manual exposure (pro)

    @ViewBuilder
    private var manualExposureControls: some View {
        VStack(spacing: 6) {
            // Auto | Manual toggle.
            HStack(spacing: 0) {
                ForEach([("Auto", false), ("Manual", true)], id: \.0) { title, m in
                    Button {
                        manualMode = m
                        if m { applyManual() } else { camera.setAutoExposure(); camera.manualExposure = false }
                    } label: {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(manualMode == m ? Color.white : Color.clear, in: Capsule())
                            .foregroundStyle(manualMode == m ? .black : .white)
                    }
                }
            }
            .padding(3).frame(maxWidth: 180)
            .background(.black.opacity(0.4), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15)))

            if manualMode {
                manualSlider("ISO", value: $manualISO,
                             range: camera.isoRange.lowerBound...camera.isoRange.upperBound,
                             display: "\(Int(manualISO))")
                manualSlider("Shutter", value: Binding(
                    get: { Float(manualShutter) },
                    set: { manualShutter = Double($0) }),
                             range: Float(camera.exposureRange.lowerBound)...Float(camera.exposureRange.upperBound),
                             display: manualShutter >= 1 ? String(format: "%.1fs", manualShutter)
                                                         : String(format: "1/%.0f", 1/manualShutter))
            }
        }
    }

    private func manualSlider(_ label: String, value: Binding<Float>,
                              range: ClosedRange<Float>, display: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).frame(width: 48, alignment: .leading)
            Slider(value: value, in: range) { editing in if !editing { applyManual() } }
                .tint(.cyan)
            Text(display).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white).frame(width: 56, alignment: .trailing)
        }
    }

    private func applyManual() {
        camera.manualExposure = true
        camera.setManualExposure(iso: manualISO, seconds: manualShutter)
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
