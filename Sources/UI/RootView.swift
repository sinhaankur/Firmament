import SwiftUI
import CoreImage
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Identifiable wrapper so a captured or imported CIImage can drive a
/// `fullScreenCover(item:)` into the editor, carrying any capture metadata.
private struct EditableImage: Identifiable {
    let id = UUID()
    let image: CIImage
    let meta: AutoDevelop.CaptureMeta
}

extension UIImage {
    /// Return a copy with EXIF orientation baked into the pixels (orientation
    /// = .up), so downstream CIImage/CGImage rendering isn't rotated/mirrored.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
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
    @StateObject private var timelapse = TimelapseRecorder()

    @State private var mode: Mode = .explore
    @State private var selected: SkyObject?
    @State private var showTelescope = false
    @State private var showSettings = false
    @State private var libraryPick: PhotosPickerItem?
    @State private var importedForEditing: CIImage?
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("showConstellations") private var showConstellations = true
    @AppStorage("nightVision") private var nightVision = false
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

            // Explore reticle + compass HUD (aim-to-identify).
            if mode == .explore {
                ExploreHUD(model: model) { obj in selected = obj }
                    .padding(.top, 60)
                    .padding(.bottom, 120)
                    .allowsHitTesting(true)
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
                                    camera: camera,
                                    timelapse: timelapse,
                                    profile: camera.profile,
                                    advice: advisor.advice,
                                    inFrame: inFrameSubjects)
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
        // Night-vision red wash — preserves dark adaptation (every serious
        // stargazing app has this). Multiply keeps the sky visible, killed blue/green.
        .overlay {
            if nightVision {
                Color.red.opacity(0.32)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: nightVision)
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: selected?.id)
        .animation(.easeInOut(duration: 0.35), value: hasOnboarded)
        .onAppear {
            // Only start sensors (and trigger permission prompts) once the user
            // has been primed by onboarding.
            if hasOnboarded { startSensors() }
        }
        .onChange(of: camera.isConfigured) { _, ready in
            if ready { night.attach(to: camera); timelapse.configure(night: night) }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .capture {
                OnDeviceLLM.shared.prewarm()   // warm the model before we phrase
                Task { await refreshAdvice() }
            }
        }
        .sheet(isPresented: $showTelescope) {
            TelescopeSheet(telescope: telescope)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showConstellations: $showConstellations,
                          nightVision: $nightVision)
        }
        // A single editor cover for both freshly-captured and imported images —
        // two stacked fullScreenCovers don't reliably present in SwiftUI.
        .fullScreenCover(item: editingBinding) { editable in
            PhotoEditorView(original: editable.image, meta: editable.meta) {
                night.capturedForEditing = nil
                importedForEditing = nil
            }
        }
        .onChange(of: libraryPick) { _, item in
            guard let item else { return }
            Task { await loadPickedImage(item) }
        }
        .onDisappear { model.stop(); camera.stop(); telescope.disconnect() }
    }

    /// One binding that surfaces whichever image wants editing (captured or
    /// imported), so there's a single presenter.
    private var editingBinding: Binding<EditableImage?> {
        Binding(
            get: {
                if let ci = night.capturedForEditing {
                    return EditableImage(image: ci, meta: night.lastCaptureMeta)
                }
                if let ci = importedForEditing {
                    return EditableImage(image: ci, meta: .init())
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    night.capturedForEditing = nil
                    importedForEditing = nil
                }
            }
        )
    }

    /// Load a library-picked photo OR video into a CIImage and open the editor.
    /// Videos / time-lapses are frame-stacked into one brighter still. Photos are
    /// orientation-corrected (HEIC/JPEG carry EXIF rotation CIImage ignores).
    private func loadPickedImage(_ item: PhotosPickerItem) async {
        defer { Task { @MainActor in libraryPick = nil } }

        // Video / time-lapse → stack frames into one still.
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let movie = try? await item.loadTransferable(type: VideoImporter.Movie.self),
               let stacked = await VideoImporter().stackedFrame(from: movie.url),
               !stacked.extent.isEmpty, !stacked.extent.isInfinite, !stacked.extent.isNull {
                await MainActor.run { importedForEditing = stacked }
            }
            return
        }

        // Photo → decode with orientation baked in.
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        var ci: CIImage?
        if let ui = UIImage(data: data) {
            let fixed = ui.normalizedUp()
            if let cg = fixed.cgImage {
                ci = CIImage(cgImage: cg)
            } else if let c = CIImage(image: fixed) {
                ci = c
            }
        }
        if ci == nil {
            ci = CIImage(data: data, options: [.applyOrientationProperty: true])
        }
        guard let image = ci, !image.extent.isEmpty, !image.extent.isInfinite, !image.extent.isNull else { return }
        await MainActor.run { importedForEditing = image }
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

    /// Named bright objects roughly within the camera's frame right now, so a
    /// capture can be annotated with what it's pointing at.
    private var inFrameSubjects: [String] {
        let aimAz = model.motion.pointingAzimuth
        let aimAlt = model.motion.pointingAltitude
        let hFov = camera.horizontalFovDegrees
        return model.objects
            .filter { $0.altitude > 0 && ($0.kind != .star || ($0.magnitude ?? 9) < 1.6) }
            .filter { obj in
                var dAz = obj.azimuth - aimAz
                while dAz > 180 { dAz -= 360 }
                while dAz < -180 { dAz += 360 }
                return abs(dAz) < hFov * 0.6 && abs(obj.altitude - aimAlt) < hFov * 0.6
            }
            .prefix(6)
            .map(\.name)
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
            // Open an existing photo, video, or timelapse to auto-develop + edit.
            PhotosPicker(selection: $libraryPick,
                         matching: .any(of: [.images, .videos])) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
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
