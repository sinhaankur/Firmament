import SwiftUI
import AVFoundation

/// **CameraEngine** — one of the app's two named engines (the other is
/// `NightSkyEngine`). It owns the live camera session, selects the strongest
/// back lens, detects the device's real capture limits (`DeviceCaptureProfile`),
/// and vends the session to the `NightCapture` pipeline.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
final class CameraEngine: ObservableObject {
    /// The capture session lives on its own serial queue; `nonisolated(unsafe)`
    /// because `AVCaptureSession` is internally thread-safe for the
    /// begin/commit/start calls we make and we always touch it on `sessionQueue`.
    nonisolated(unsafe) let session = AVCaptureSession()
    @Published var isConfigured = false
    @Published var lastError: String?
    /// The honest capabilities of the active camera, discovered at runtime.
    @Published var profile: DeviceCaptureProfile?

    private let sessionQueue = DispatchQueue(label: "nightsky.camera.session")
    nonisolated(unsafe) private(set) var videoDevice: AVCaptureDevice?

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Prefer the best available back camera. On a Pro device the main
            // (wide) sensor is the largest and gathers the most light — the
            // right lens for the night sky. We deliberately favour the single
            // largest sensor over the fused virtual devices for astro, where a
            // clean long exposure beats computational fusion.
            let device = Self.bestBackCamera()
            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                Task { @MainActor in self.lastError = "No back camera available." }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.videoDevice = device
            self.session.commitConfiguration()

            self.session.startRunning()

            // Interrogate the hardware for its real limits (ProRAW is filled in
            // later when NightCapture attaches its photo output).
            let prof = DeviceCaptureProfile.detect(from: device, photoOutput: nil)
            Task { @MainActor in
                self.profile = prof
                self.isConfigured = true
            }
        }
    }

    /// Called by `NightCapture` once its photo output exists, so ProRAW support
    /// is reflected in the published profile.
    func refreshProfile(proRAWAvailable: Bool) {
        guard let device = videoDevice else { return }
        var prof = DeviceCaptureProfile.detect(from: device, photoOutput: nil)
        prof = DeviceCaptureProfile(
            modelName: prof.modelName,
            maxExposureSeconds: prof.maxExposureSeconds,
            minExposureSeconds: prof.minExposureSeconds,
            maxISO: prof.maxISO, minISO: prof.minISO,
            proRAWAvailable: proRAWAvailable,
            maxMegapixels: prof.maxMegapixels,
            horizontalFovDegrees: prof.horizontalFovDegrees,
            apertureFStop: prof.apertureFStop
        )
        profile = prof
    }

    /// Pick the strongest back camera for low light, in priority order:
    /// main wide (biggest sensor) → dual/triple fusion → any wide.
    private static func bestBackCamera() -> AVCaptureDevice? {
        let wanted: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,   // main sensor — largest, best in the dark
            .builtInTripleCamera,
            .builtInDualCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: wanted, mediaType: .video, position: .back
        )
        // Prefer the plain wide-angle (largest single sensor) if present.
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? discovery.devices.first
    }

    /// Horizontal field of view for the active device format — read from the
    /// hardware, not guessed, so labels land on the real objects on any lens.
    var horizontalFovDegrees: Double {
        guard let fmt = videoDevice?.activeFormat else { return 67 }
        return Double(fmt.videoFieldOfView)
    }

    // MARK: - Zoom

    /// Current zoom factor (1.0 = the lens's native field of view).
    @Published var zoomFactor: CGFloat = 1.0

    /// The maximum zoom we allow — capped well below the hardware max because
    /// heavy digital zoom is just cropping (noisy on faint sky).
    var maxAllowedZoom: CGFloat {
        guard let d = videoDevice else { return 1 }
        return min(d.activeFormat.videoMaxZoomFactor, 10)
    }

    /// Zoom factors at/below which the switch is still *optical* (lens change),
    /// not digital cropping — good to know, since optical keeps quality.
    var opticalZoomStops: [CGFloat] {
        videoDevice?.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) } ?? []
    }

    /// True if the current zoom is still within an optical stop (no quality loss).
    var isOpticalZoom: Bool {
        guard let maxOptical = opticalZoomStops.max() else { return zoomFactor <= 1.01 }
        return zoomFactor <= maxOptical + 0.01
    }

    /// Set the zoom factor (clamped), on the device.
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        let clamped = max(1, min(maxAllowedZoom, factor))
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
        zoomFactor = clamped
    }

    // MARK: - Manual focus (pro mode)

    /// Whether the user has taken manual focus control.
    @Published var manualFocus = false
    /// Lens position 0 (near) … 1 (infinity). Stars want ~1.0.
    @Published var lensPosition: Float = 1.0

    /// Lock focus at a specific lens position (1.0 ≈ infinity, for stars).
    func setManualFocus(_ position: Float) {
        guard let device = videoDevice, device.isFocusModeSupported(.locked) else { return }
        let p = min(1, max(0, position))
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: p, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
        lensPosition = p
    }

    func setAutoFocus() {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Manual exposure (pro mode)

    /// Whether the user has taken manual control of exposure/ISO.
    @Published var manualExposure = false
    /// The device's honest ISO + exposure-duration ranges (for slider bounds).
    var isoRange: ClosedRange<Float> {
        guard let f = videoDevice?.activeFormat else { return 100...3200 }
        return f.minISO...f.maxISO
    }
    var exposureRange: ClosedRange<Double> {
        guard let f = videoDevice?.activeFormat else { return 0.001...1 }
        return f.minExposureDuration.seconds...f.maxExposureDuration.seconds
    }

    /// Apply a manual ISO + shutter (seconds), clamped to the device limits.
    func setManualExposure(iso: Float, seconds: Double) {
        guard let device = videoDevice else { return }
        let clampedISO = min(max(isoRange.lowerBound, iso), isoRange.upperBound)
        let clampedSec = min(max(exposureRange.lowerBound, seconds), exposureRange.upperBound)
        let duration = CMTime(seconds: clampedSec, preferredTimescale: 1_000_000)
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// Return exposure to the automatic algorithm.
    func setAutoExposure() {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }
}

/// SwiftUI wrapper around an AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
