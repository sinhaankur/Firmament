//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation
import AVFoundation
import CoreImage
import UIKit
import Photos

/// The night-sky capture pipeline. It pushes the camera as far as the hardware
/// allows, choosing the right tool for the current stability:
///
///   • **Long exposure** — manual `AVCaptureDevice` exposure at max ISO and the
///     longest supported `exposureDuration` (hardware-capped, ~1 s on iPhone).
///   • **Frame stacking** — capture N frames and average/accumulate them to beat
///     that cap: less noise, more faint-star signal, no motion blur when steady.
///   • **System night-mode assist** — where the photo output offers a long
///     capture, we let it run to its maximum.
///
/// Which path runs is gated on `StabilityDetector`: hand-held falls back to a
/// single best-effort frame; tripod-steady unlocks the full stack.
@MainActor
final class NightCapture: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case capturing(progress: Double)
        case processing
        case saved
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var lastImage: UIImage?
    /// The freshly captured frame, handed to the editor for review + tweaks
    /// before saving. Set when a capture finishes; cleared when the editor closes.
    @Published var capturedForEditing: CIImage?
    /// Increments each time a capture completes — a reliable change signal for
    /// the UI (CIImage isn't Equatable, and identity can repeat).
    @Published var captureSerial: Int = 0
    /// What the last capture was shot with — fed to the editor's AutoDevelop so
    /// it can reason about the exposure the frame was taken at.
    @Published var lastCaptureMeta = AutoDevelop.CaptureMeta()
    /// Objects that were in frame at capture time (set by the caller).
    var inFrameAnnotation: [String] = []

    /// When set, finished frames are routed here (for the time-lapse recorder)
    /// instead of opening the editor.
    var onFrameForTimelapse: ((CGImage) -> Void)?

    /// Optional master dark for dark-frame subtraction (removes thermal noise +
    /// hot pixels). When calibrated + enabled, each light frame is corrected.
    weak var darkStore: DarkFrameStore?
    /// Whether we're currently capturing a dark-calibration frame (route it to
    /// the dark store instead of the editor/stack).
    var capturingDark = false
    /// User toggle for applying subtraction to real captures.
    var darkSubtractionEnabled = false
    /// Dithering: nudge each light frame by a tiny random offset before stacking
    /// so residual fixed-pattern / walking noise averages out. On by default.
    var ditherEnabled = true

    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext()
    private weak var controller: CameraEngine?

    /// True when the sensor supports Apple ProRAW on this device — the best
    /// possible night-sky negative (full bit depth, minimal processing).
    private(set) var proRAWAvailable = false

    /// Attach to an already-configured camera session and unlock the pro
    /// ceiling: highest quality prioritization, maximum photo dimensions, and
    /// Apple ProRAW where the hardware supports it.
    func attach(to controller: CameraEngine) {
        self.controller = controller
        let session = controller.session
        session.beginConfiguration()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // Squeeze the most out of the Pro sensor.
        photoOutput.maxPhotoQualityPrioritization = .quality
        if #available(iOS 16.0, *) {
            // Full-resolution frames (e.g. 48 MP on iPhone Pro sensors).
            photoOutput.maxPhotoDimensions = maxSupportedDimensions()
        }
        // Apple ProRAW — the cleanest astro negative when available.
        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = true
            proRAWAvailable = true
        }

        session.commitConfiguration()

        // Reflect ProRAW support in the engine's published capability profile.
        controller.refreshProfile(proRAWAvailable: proRAWAvailable)
    }

    /// Largest still dimensions the active format supports.
    @available(iOS 16.0, *)
    private func maxSupportedDimensions() -> CMVideoDimensions {
        guard let fmt = controller?.videoDevice?.activeFormat,
              let maxDim = fmt.supportedMaxPhotoDimensions.max(by: {
                  Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
              }) else {
            return CMVideoDimensions(width: 0, height: 0)
        }
        return maxDim
    }

    private var darkFramesLeft = 0

    // MARK: - Dark-frame calibration

    /// Capture a master dark: several covered-lens frames averaged. The caller
    /// should have the user cover the lens first. Uses the same exposure/ISO as a
    /// real capture so the thermal signal matches.
    func calibrateDark(frames: Int = 5) {
        guard let device = controller?.videoDevice, let darkStore else { return }
        pushToLimits(device)
        darkStore.beginCalibration()
        capturingDark = true
        darkFramesLeft = frames
        state = .capturing(progress: 0)
        captureDarkFrame()
    }

    private func captureDarkFrame() {
        photoOutput.capturePhoto(with: makePhotoSettings(preferRAW: false), delegate: self)
    }

    // MARK: - Capture entry

    /// Capture a single time-lapse frame: one processed frame at the device's
    /// current (max) settings, routed to `onFrameForTimelapse`.
    func captureTimelapseFrame() {
        guard let device = controller?.videoDevice else { return }
        pushToLimits(device)
        stackTarget = 0
        photoOutput.capturePhoto(with: makePhotoSettings(preferRAW: false), delegate: self)
    }

    /// Capture the night sky. `stacked` decides how many frames to accumulate;
    /// callers pass a bigger count when the phone is tripod-steady.
    func capture(stackFrames: Int) {
        guard let device = controller?.videoDevice else {
            state = .failed("Camera not ready"); return
        }
        state = .capturing(progress: 0)
        pushToLimits(device)

        // Record what we're shooting with, for the editor's AutoDevelop.
        lastCaptureMeta = AutoDevelop.CaptureMeta(
            iso: Double(device.iso),
            exposureSeconds: device.exposureDuration.seconds,
            isStacked: stackFrames > 1,
            frameCount: max(1, stackFrames)
        )

        if stackFrames <= 1 {
            captureSingle()
        } else {
            captureStack(count: stackFrames)
        }
    }

    // MARK: - Drive the device to its ceiling

    /// Configure the device for stars: focus locked at infinity, the longest
    /// exposure and highest ISO the hardware allows, and a fixed daylight-ish
    /// white balance so auto-WB doesn't tint the night sky. All clamped to the
    /// active format's real limits.
    private func pushToLimits(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // Focus: lock at infinity — stars are at the far end of the lens.
            if device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)
            }

            // Exposure: in Auto mode, drive to the longest duration + top ISO
            // for maximum light. In Manual mode, leave the user's exposure alone.
            if controller?.manualExposure != true {
                let fmt = device.activeFormat
                let maxDur = fmt.maxExposureDuration
                let maxISO = fmt.maxISO
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(
                        duration: maxDur, iso: maxISO, completionHandler: nil
                    )
                }
            }

            // White balance: lock to a neutral daylight point (~5200K) so the
            // sky stays true instead of being auto-warmed toward city light.
            if device.isWhiteBalanceModeSupported(.locked) {
                let gains = daylightGains(for: device)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }

            // Note: we no longer force zoom to 1.0 here — the user's chosen zoom
            // (great for the Moon/planets) is respected. The Capture UI warns
            // when zoom crosses into digital-crop territory on faint sky.

            device.unlockForConfiguration()
        } catch {
            // Non-fatal: fall back to whatever auto gives us.
        }
    }

    /// Neutral daylight white-balance gains, clamped to the device maximum.
    private func daylightGains(for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let temp = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: 5200, tint: 0)
        var g = device.deviceWhiteBalanceGains(for: temp)
        let maxG = device.maxWhiteBalanceGain
        g.redGain = min(max(1.0, g.redGain), maxG)
        g.greenGain = min(max(1.0, g.greenGain), maxG)
        g.blueGain = min(max(1.0, g.blueGain), maxG)
        return g
    }

    // MARK: - Single best-effort frame (hand-held or night-mode assist)

    private func captureSingle() {
        // A single hero frame: use the best possible negative (ProRAW).
        photoOutput.capturePhoto(with: makePhotoSettings(preferRAW: true), delegate: self)
    }

    /// Build capture settings.
    /// - Parameter preferRAW: request ProRAW/RAW for the cleanest single frame.
    ///   Stacking passes `false` — many fast processed frames align + average
    ///   into a result that beats one RAW for noise, without the per-frame cost.
    private func makePhotoSettings(preferRAW: Bool) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings

        // Best negative first (when asked): Apple ProRAW, then plain RAW,
        // otherwise a fast HEVC frame for stacking.
        if preferRAW, photoOutput.isAppleProRAWEnabled,
           let raw = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
        } else if preferRAW, let raw = photoOutput.availableRawPhotoPixelFormatTypes.first {
            settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
        } else if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        // Quality over speed — the tripod means we can afford the full pass.
        settings.photoQualityPrioritization = .quality

        // Capture at the sensor's maximum resolution (48 MP on Pro sensors).
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        return settings
    }

    // MARK: - Frame stacking (tripod)

    private var stackAccumulator: CIImage?
    private var stackCount = 0
    private var stackTarget = 0

    private func captureStack(count: Int) {
        stackAccumulator = nil
        stackCount = 0
        stackTarget = count
        captureNextStackFrame()
    }

    private func captureNextStackFrame() {
        guard stackCount < stackTarget else {
            finishStack(); return
        }
        // Fast processed frames for the stack (RAW is reserved for single shots).
        photoOutput.capturePhoto(with: makePhotoSettings(preferRAW: false), delegate: self)
    }

    /// Average frames together. Averaging N frames drops read-noise by √N while
    /// keeping star signal — the core of astro stacking. (Alignment via feature
    /// matching lands in Phase 3; on a tripod frames are already registered.)
    private func accumulate(_ rawFrame: CIImage) {
        // Dark-frame subtraction: remove thermal noise + hot pixels per light.
        var frame = (darkSubtractionEnabled && darkStore?.isCalibrated == true)
            ? (darkStore?.subtract(from: rawFrame) ?? rawFrame)
            : rawFrame
        // Dithering: nudge this frame by a tiny random offset so fixed-pattern /
        // walking noise averages out across the stack instead of reinforcing.
        if ditherEnabled {
            frame = Self.dither(frame)
        }
        stackCount += 1
        if let acc = stackAccumulator {
            let weightNew = 1.0 / Double(stackCount)
            let blend = CIFilter(name: "CIDissolveTransition", parameters: [
                kCIInputImageKey: acc,
                kCIInputTargetImageKey: frame,
                kCIInputTimeKey: weightNew,
            ])
            stackAccumulator = blend?.outputImage ?? acc
        } else {
            stackAccumulator = frame
        }
        state = .capturing(progress: Double(stackCount) / Double(stackTarget))
        captureNextStackFrame()
    }

    /// Nudge a frame by a small random translation (±1.5 px) then re-origin, so
    /// residual fixed-pattern noise decorrelates across the stack. The offset is
    /// tiny enough that star signal still averages cleanly on a steady tripod.
    static func dither(_ image: CIImage) -> CIImage {
        let dx = CGFloat.random(in: -1.5...1.5)
        let dy = CGFloat.random(in: -1.5...1.5)
        // Clamp first so the shift can't uncover an edge, then crop back to the
        // exact original extent — the frame stays the same size for aligned blend.
        let shifted = image.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
        return shifted.cropped(to: image.extent)
    }

    private func finishStack() {
        state = .processing
        guard let acc = stackAccumulator,
              let cg = ciContext.createCGImage(acc, from: acc.extent) else {
            state = .failed("Stacking failed"); return
        }
        lastImage = UIImage(cgImage: cg)
        // Hand the stacked result to the editor for review before saving.
        capturedForEditing = CIImage(cgImage: cg)
        captureSerial += 1
        state = .idle
    }

    // MARK: - Hand-off to editor / save

    /// A single captured frame → hand to the editor (no auto-save; the user
    /// reviews, optionally enhances, then saves).
    private func renderAndSave(_ ci: CIImage) {
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else {
            state = .failed("Could not render frame"); return
        }
        lastImage = UIImage(cgImage: cg)
        capturedForEditing = CIImage(cgImage: cg)
        captureSerial += 1
        state = .idle
    }

    private func save(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self?.state = .failed("Photos access denied") }
                return
            }
            let box = self   // capture once so the nested completion is Sendable-clean
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetChangeRequest.creationRequestForAsset(from: image)
                // Stamp what was in frame + when, so the shot is annotated.
                req.creationDate = Date()
            }, completionHandler: { ok, _ in
                Task { @MainActor in box?.state = ok ? .saved : .failed("Save failed") }
            })
        }
    }
}

extension NightCapture: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.state = .failed("No image data") }
            return
        }
        // CoreImage decodes both processed frames and RAW/DNG (ProRAW) — the
        // right path when the negative is a RAW file UIImage can't render.
        guard let ci = CIImage(data: data) else {
            Task { @MainActor in self.state = .failed("Could not decode frame") }
            return
        }
        Task { @MainActor in
            // Dark-calibration frame? Route to the dark store.
            if self.capturingDark {
                self.darkStore?.addDarkFrame(ci)
                self.darkFramesLeft -= 1
                if self.darkFramesLeft <= 0 {
                    self.capturingDark = false
                    let iso = Double(self.controller?.videoDevice?.iso ?? 0)
                    let exp = self.controller?.videoDevice?.exposureDuration.seconds ?? 0
                    self.darkStore?.finishCalibration(iso: Float(iso), exposure: exp)
                    self.state = .idle
                } else {
                    self.captureDarkFrame()
                }
                return
            }
            // Time-lapse frame? Route to the recorder instead of the editor.
            if let sink = self.onFrameForTimelapse {
                if let cg = self.ciContext.createCGImage(ci, from: ci.extent) {
                    sink(cg)
                }
                return
            }
            if self.stackTarget > 1 {
                self.accumulate(ci)
            } else {
                self.renderAndSave(ci)
            }
        }
    }
}
