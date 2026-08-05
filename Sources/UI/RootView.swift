import SwiftUI

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
                    horizontalFovDegrees: camera.horizontalFovDegrees
                )
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
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
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: selected?.id)
        .onAppear {
            model.start()
            camera.configure()
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
        .onDisappear { model.stop(); camera.stop(); telescope.disconnect() }
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
                Text("NightSky").font(.system(size: 15, weight: .semibold, design: .rounded))
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
