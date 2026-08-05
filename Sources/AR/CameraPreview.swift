import SwiftUI
import AVFoundation

/// A live back-camera preview. This is the sky behind the overlay.
///
/// It runs an `AVCaptureSession` with the default video device and vends the
/// same session to the capture pipeline (so Night Capture can add a photo
/// output to it). Kept deliberately small — the astronomy is the star here.
final class CameraController: ObservableObject {
    /// The capture session lives on its own serial queue; `nonisolated(unsafe)`
    /// because `AVCaptureSession` is internally thread-safe for the
    /// begin/commit/start calls we make and we always touch it on `sessionQueue`.
    nonisolated(unsafe) let session = AVCaptureSession()
    @Published var isConfigured = false
    @Published var lastError: String?

    private let sessionQueue = DispatchQueue(label: "nightsky.camera.session")
    nonisolated(unsafe) private(set) var videoDevice: AVCaptureDevice?

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Prefer a wide (or the main) back camera.
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video, position: .back
            )
            guard let device = discovery.devices.first,
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
            Task { @MainActor in self.isConfigured = true }
        }
    }

    /// Approximate field of view for the active device, used by the projection.
    var horizontalFovDegrees: Double {
        // Wide back cameras are ~65–70° horizontal; a safe default until we read
        // the exact value from the device format.
        guard let fmt = videoDevice?.activeFormat else { return 67 }
        return Double(fmt.videoFieldOfView)   // this is the horizontal FOV
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
