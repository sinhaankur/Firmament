import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Focus-peaking overlay: taps the live video, finds the sharpest (highest
/// spatial-frequency) edges, and paints them in a bright colour over the sky.
/// The classic pro focus aid — for stars, nudge manual focus until the star
/// points light up, and you're tack sharp.
///
/// It attaches its own `AVCaptureVideoDataOutput` to the shared session and
/// renders only the thresholded edge mask (transparent elsewhere), so the real
/// camera preview underneath is untouched.
///
/// © Ankur Sinha.
@MainActor
final class FocusPeakingController: NSObject, ObservableObject {
    @Published var edgeImage: CGImage?

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "nightsky.peaking")
    private let ciContext = CIContext(options: [.priorityRequestLow: true])
    nonisolated(unsafe) private weak var session: AVCaptureSession?
    private var attached = false

    /// Peaking colour.
    nonisolated(unsafe) var peakColor = CIColor(red: 1, green: 0.2, blue: 0.9)

    func attach(to session: AVCaptureSession) {
        guard !attached else { return }
        self.session = session
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canAddOutput(output) { session.addOutput(output); attached = true }
        session.commitConfiguration()
    }

    func start() { /* delegate runs while attached */ }
    func stop() { edgeImage = nil }
}

extension FocusPeakingController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: pb)

        // Edge detect (Sobel-like) → grayscale magnitude.
        let edges = CIFilter.edges()
        edges.inputImage = source
        edges.intensity = 8
        guard let edgeOut = edges.outputImage else { return }

        // Threshold: keep only strong edges, colour them, drop the rest to clear.
        let mono = CIFilter.colorControls()
        mono.inputImage = edgeOut
        mono.saturation = 0
        mono.contrast = 4          // harden the threshold
        mono.brightness = -0.35    // suppress weak edges → black
        guard let hard = mono.outputImage else { return }

        // Map luminance→alpha so only bright (in-focus) edges show, tinted.
        let tint = CIFilter.colorMatrix()
        tint.inputImage = hard
        tint.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        tint.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)   // alpha = luminance
        tint.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let alphaMask = tint.outputImage else { return }

        // Composite a solid peak colour through that alpha.
        let colorImg = CIImage(color: peakColor).cropped(to: source.extent)
        let masked = colorImg.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: source.extent),
            kCIInputMaskImageKey: alphaMask,
        ])

        guard let cg = ciContext.createCGImage(masked, from: source.extent) else { return }
        Task { @MainActor in self.edgeImage = cg }
    }
}

/// SwiftUI overlay that draws the current peaking mask.
struct FocusPeakingOverlay: View {
    @ObservedObject var controller: FocusPeakingController

    var body: some View {
        GeometryReader { _ in
            if let cg = controller.edgeImage {
                Image(decorative: cg, scale: 1, orientation: .right)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
                    .opacity(0.9)
            }
        }
        .ignoresSafeArea()
    }
}
