import SwiftUI
import CoreImage

/// Identifiable wrapper so a freshly captured CIImage can drive a
/// `fullScreenCover(item:)` into the editor.
private struct EditableImage: Identifiable {
    let id = UUID()
    let image: CIImage
}

/// The whole app: a full-screen camera sky with a minimal mode switcher.
/// Explore (identify) · Spot (satellites) · Capture (night photo).
struct RootView: View {
    enum Mode: String, CaseIterable { case explore = "Explore", spot = "Spot", capture = "Capture" }

    @StateObject private var model = SkyViewModel()
    @StateObject private var camera = CameraEngine()
    @StateObject private var night = NightCapture()
    @StateObject private var advisor = CaptureAdvisor()
    @StateObject private var telescope = TelescopeEngine()

    @State private var mode: Mode = .explore
    @State private var selected: SkyObject?
    @State private var showTelescope = false
    @State private var showSettings = false
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("showConstellations") private var showConstellations = true
    private let weather = WeatherProvider()

    var body: some View {
        ZStack {
            // Live sky.
            if camera.isConfigured {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Celestial overlay (Explore + Spot both show it).
            if mode != .capture || true {
                SkyOverlayView(
                    model: model,
                    selected: $selected,
                    showConstellations: showConstellations,
                    horizontalFovDegrees: camera.horizontalFovDegrees
                )
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                if mode == .spot {
                    SpotView(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if mode == .capture {
                    CaptureControls(night: night, motion: model.motion,
                                    profile: camera.profile,
                                    advice: advisor.advice)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                modeSwitcher
            }
            .padding()

            // Info card for a tapped object.
            if let obj = selected {
                InfoCard(
                    object: obj,
                    onClose: { selected = nil },
                    onGoto: { telescope.goto(obj) },
                    telescopeConnected: telescope.isConnected
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // First-launch onboarding + permission priming (over everything).
            if !hasOnboarded {
                OnboardingView { hasOnboarded = true; startSensors() }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: selected?.id)
        .animation(.easeInOut(duration: 0.35), value: hasOnboarded)
        .onAppear {
            // Only start sensors (and trigger permission prompts) once the user
            // has been primed by onboarding.
            if hasOnboarded { startSensors() }
        }
        .onChange(of: camera.isConfigured) { _, ready in
            if ready { night.attach(to: camera) }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .capture { Task { await refreshAdvice() } }
        }
        .sheet(isPresented: $showTelescope) {
            TelescopeSheet(telescope: telescope)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showConstellations: $showConstellations)
        }
        .fullScreenCover(item: Binding(
            get: { night.capturedForEditing.map { EditableImage(image: $0) } },
            set: { if $0 == nil { night.capturedForEditing = nil } }
        )) { editable in
            PhotoEditorView(original: editable.image, meta: night.lastCaptureMeta) {
                night.capturedForEditing = nil
            }
        }
        .onDisappear { model.stop(); camera.stop(); telescope.disconnect() }
    }

    /// Start the sensors + camera. Called after onboarding, so the system
    /// permission prompts appear only once the user understands why.
    private func startSensors() {
        model.start()
        camera.configure()
    }

    // MARK: - Capture advice

    /// Assemble real conditions (astronomy from NightSkyEngine + optional
    /// weather) and ask the advisor what to shoot. Runs only in Capture mode.
    private func refreshAdvice() async {
        let now = model.date
        let sun = model.objects.first { $0.id == "sun" }
        let moon = model.objects.first { $0.id == "moon" }
        let moonIllum = moonIllumination(at: now)

        var reading: WeatherProvider.Reading?
        if let coord = model.location.coordinate {
            reading = await weather.fetch(for: coord)
        }

        let conditions = SkyConditions(
            cloudCover: reading?.cloudCover,
            humidity: reading?.humidity,
            moonIllumination: moonIllum,
            moonAltitude: moon?.altitude ?? -90,
            sunAltitude: sun?.altitude ?? -90,
            bortle: nil,
            windSpeed: reading?.windSpeed,
            temperatureC: reading?.temperatureC
        )
        advisor.update(conditions: conditions, profile: camera.profile)
    }

    private func moonIllumination(at date: Date) -> Double {
        let jd = SkyMath.julianDay(from: date)
        return SolarSystem.moonPhase(jd: jd).illumination
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Firmament").font(.system(size: 15, weight: .semibold, design: .rounded))
                if model.usingSimulatedLocation {
                    Label("Locating…", systemImage: "location.slash")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                } else if !model.location.headingIsReliable {
                    Label("Calibrate compass — move in a figure 8",
                          systemImage: "safari")
                        .font(.system(size: 10)).foregroundStyle(.yellow)
                }
            }
            Spacer()
            Button {
                showTelescope = true
            } label: {
                Image(systemName: telescope.isConnected ? "scope" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(telescope.isConnected ? .green : .white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Text(model.date, style: .time)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                modeButton(m)
            }
        }
        .padding(4)
        .background(.black.opacity(0.4), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15)))
    }

    private func modeButton(_ m: Mode) -> some View {
        let isActive = mode == m
        return Button {
            mode = m
            if m != .explore { selected = nil }
        } label: {
            Text(m.rawValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isActive ? Color.black : Color.white)
                .background(isActive ? Color.white : Color.clear, in: Capsule())
        }
    }
}
