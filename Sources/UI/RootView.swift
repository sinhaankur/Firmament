//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
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
    @StateObject private var peaking = FocusPeakingController()
    @StateObject private var darkStore = DarkFrameStore()

    @State private var mode: Mode = .explore
    @State private var selected: SkyObject?
    @State private var showTelescope = false
    @State private var showSettings = false
    @State private var libraryPick: PhotosPickerItem?
    /// The image currently open in the editor (from capture OR import).
    @State private var editingItem: EditableImage?
    /// Surfaced if a library item can't be loaded, so failure isn't silent.
    @State private var importError: String?
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("showConstellations") private var showConstellations = true
    @AppStorage("nightVision") private var nightVision = false
    /// Pure Photography: hide all astronomy overlays, just the camera + controls.
    @AppStorage("pureMode") private var pureMode = false
    @AppStorage("showGrid") private var showGrid = false
    @State private var peakingOn = false
    @Environment(\.scenePhase) private var scenePhase
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

            // Focus-peaking overlay (Capture mode, when enabled).
            if mode == .capture && peakingOn {
                FocusPeakingOverlay(controller: peaking)
            }

            // Celestial overlay — shown everywhere EXCEPT Pure Photography in
            // Capture, where we want a clean, distraction-free frame.
            let cleanShoot = mode == .capture && pureMode
            if !cleanShoot {
                SkyOverlayView(
                    model: model,
                    selected: $selected,
                    showConstellations: showConstellations,
                    horizontalFovDegrees: camera.horizontalFovDegrees
                )
                .ignoresSafeArea()
            }

            // Composition grid (rule-of-thirds) — for framing in Pure mode.
            if mode == .capture && showGrid {
                CompositionGrid()
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
                                    inFrame: inFrameSubjects,
                                    peakingOn: $peakingOn,
                                    pureMode: $pureMode,
                                    showGrid: $showGrid,
                                    darkStore: darkStore)
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

            // Photo editor — presented as a top-level overlay (NOT a system
            // sheet/cover) so it can never conflict with the Photos picker's own
            // presentation. This is what fixes "picker closes, nothing opens".
            if let editable = editingItem {
                PhotoEditorView(original: editable.image, meta: editable.meta) {
                    editingItem = nil
                    night.capturedForEditing = nil
                }
                .transition(.opacity)
                .zIndex(20)
                .ignoresSafeArea()
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
            if ready {
                night.attach(to: camera)
                night.darkStore = darkStore
                timelapse.configure(night: night)
                peaking.attach(to: camera.session)
            }
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
        // (The editor is presented as a top-level ZStack overlay above, not a
        // system cover, so it never conflicts with the Photos picker sheet.)
        // Capture finished → open the editor.
        .onChange(of: night.captureSerial) { _, _ in
            if let ci = night.capturedForEditing {
                editingItem = EditableImage(image: ci, meta: night.lastCaptureMeta)
            }
        }
        // Library item chosen → load then open the editor.
        .onChange(of: libraryPick) { _, item in
            guard let item else { return }
            Task { await loadPickedImage(item) }
        }
        .alert("Couldn't open that item",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        // Pause sensors + camera when backgrounded (battery), resume on return.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if hasOnboarded { startSensors() }
            case .background, .inactive:
                model.stop(); camera.stop()
            @unknown default: break
            }
        }
        .onDisappear { model.stop(); camera.stop(); telescope.disconnect() }
    }

    /// Load a library-picked photo OR video into a CIImage and open the editor.
    /// Videos / time-lapses are frame-stacked into one brighter still. Photos are
    /// orientation-corrected (HEIC/JPEG carry EXIF rotation CIImage ignores).
    private func loadPickedImage(_ item: PhotosPickerItem) async {
        var loaded: CIImage?
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }

        if isVideo {
            // Video / time-lapse → stack frames into one still.
            if let movie = try? await item.loadTransferable(type: VideoImporter.Movie.self) {
                loaded = await VideoImporter().stackedFrame(from: movie.url)
            }
        } else {
            let isRAW = item.supportedContentTypes.contains {
                $0.conforms(to: .rawImage) || $0.identifier.contains("dng")
            }
            if let data = try? await item.loadTransferable(type: Data.self) {
                // RAW / ProRAW (DNG) → decode via CIRAWFilter for full editing
                // latitude (the real reason to shoot RAW).
                if isRAW,
                   let raw = CIRAWFilter(imageData: data, identifierHint: nil),
                   let out = raw.outputImage {
                    loaded = out
                }
                // Otherwise a normal photo: decode with orientation baked in.
                if loaded == nil, let ui = UIImage(data: data) {
                    let fixed = ui.normalizedUp()
                    if let cg = fixed.cgImage { loaded = CIImage(cgImage: cg) }
                    else { loaded = CIImage(image: fixed) }
                }
                if loaded == nil {
                    loaded = CIImage(data: data, options: [.applyOrientationProperty: true])
                }
            }
        }

        // Reset the picker binding so the same item can be re-picked later, and
        // so its sheet is fully torn down before we present the editor.
        await MainActor.run { libraryPick = nil }

        guard let image = loaded,
              !image.extent.isEmpty, !image.extent.isInfinite, !image.extent.isNull else {
            await MainActor.run { importError = "That photo or video couldn't be decoded (it may still be downloading from iCloud)." }
            return
        }

        // Small settle so the picker sheet is gone, then show the editor overlay.
        try? await Task.sleep(nanoseconds: 250_000_000)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                editingItem = EditableImage(image: image, meta: .init())
            }
        }
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
            .accessibilityLabel("Telescope")
            // Open an existing photo, video, or timelapse to auto-develop + edit.
            PhotosPicker(selection: $libraryPick,
                         matching: .any(of: [.images, .videos])) {   // .images includes RAW/DNG
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Open a photo or video to edit")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Settings")
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
        .accessibilityLabel("\(m.rawValue) mode")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
