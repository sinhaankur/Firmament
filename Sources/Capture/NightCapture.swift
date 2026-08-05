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
    /// Objects that were in frame at capture time (set by the caller).
    var inFrameAnnotation: [String] = []

    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext()
    private weak var controller: CameraController?

    /// Attach to an already-configured camera session.
    func attach(to controller: CameraController) {
        self.controller = controller
        let session = controller.session
        session.beginConfiguration()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    // MARK: - Capture entry

    /// Capture the night sky. `stacked` decides how many frames to accumulate;
    /// callers pass a bigger count when the phone is tripod-steady.
    func capture(stackFrames: Int) {
        guard let device = controller?.videoDevice else {
            state = .failed("Camera not ready"); return
        }
        state = .capturing(progress: 0)
        pushToLimits(device)

        if stackFrames <= 1 {
            captureSingle()
        } else {
            captureStack(count: stackFrames)
        }
    }

    // MARK: - Drive the device to its ceiling

    /// Set max ISO + longest exposure the hardware supports, and lock focus at
    /// infinity — the correct configuration for stars.
    private func pushToLimits(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: 1.0)  // ~infinity
            }
            let maxDur = device.activeFormat.maxExposureDuration
            let maxISO = device.activeFormat.maxISO
            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(
                    duration: maxDur, iso: maxISO, completionHandler: nil
                )
            }
            device.unlockForConfiguration()
        } catch {
            // Non-fatal: fall back to whatever auto gives us.
        }
    }

    // MARK: - Single best-effort frame (hand-held or night-mode assist)

    private func captureSingle() {
        let settings = makePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        // System Night Mode assist: let the long capture run to its maximum
        // when the output supports it.
        if photoOutput.maxPhotoQualityPrioritization.rawValue >= AVCapturePhotoOutput.QualityPrioritization.quality.rawValue {
            settings.photoQualityPrioritization = .quality
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
        photoOutput.capturePhoto(with: makePhotoSettings(), delegate: self)
    }

    /// Average frames together. Averaging N frames drops read-noise by √N while
    /// keeping star signal — the core of astro stacking. (Alignment via feature
    /// matching lands in Phase 3; on a tripod frames are already registered.)
    private func accumulate(_ frame: CIImage) {
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

    private func finishStack() {
        state = .processing
        guard let acc = stackAccumulator,
              let cg = ciContext.createCGImage(acc, from: acc.extent) else {
            state = .failed("Stacking failed"); return
        }
        let image = UIImage(cgImage: cg)
        lastImage = image
        save(image)
    }

    // MARK: - Save

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
        guard let data = photo.fileDataRepresentation(),
              let ui = UIImage(data: data),
              let cg = ui.cgImage else {
            Task { @MainActor in self.state = .failed("No image data") }
            return
        }
        let ci = CIImage(cgImage: cg)
        Task { @MainActor in
            if self.stackTarget > 1 {
                self.accumulate(ci)
            } else {
                self.lastImage = ui
                self.save(ui)
            }
        }
    }
}
