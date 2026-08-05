import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// A "master dark" for dark-frame subtraction — the standard astrophotography
/// technique for removing **thermal noise and hot pixels**. You shoot a few
/// frames with the lens *covered* (same ISO and exposure as your real shots);
/// they capture only the sensor's fixed-pattern noise. Subtracting that from
/// each light frame cancels the hot pixels and thermal signal that no amount of
/// stacking can remove.
///
/// This is calibration data, held in memory for the session. It's only valid
/// while the capture settings (and roughly the sensor temperature) match.
///
/// © Ankur Sinha.
@MainActor
final class DarkFrameStore: ObservableObject {
    /// The averaged master dark, if calibrated.
    private(set) var master: CIImage?
    /// True once a valid dark has been captured.
    @Published var isCalibrated = false
    /// The settings the dark was shot at, so we can warn if lights differ.
    @Published var calibratedISO: Float = 0
    @Published var calibratedExposure: Double = 0
    /// Mean brightness of the captured dark (should be near-black; a bright value
    /// means the lens wasn't actually covered).
    @Published var darkMeanLuma: Double = 0

    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private var accumulator: CIImage?
    private var count = 0

    /// Begin a fresh calibration.
    func beginCalibration() {
        accumulator = nil
        count = 0
        isCalibrated = false
    }

    /// Add one covered-lens frame to the master (averaged).
    func addDarkFrame(_ frame: CIImage) {
        count += 1
        if let acc = accumulator {
            let w = 1.0 / Double(count)
            let blend = CIFilter(name: "CIDissolveTransition", parameters: [
                kCIInputImageKey: acc,
                kCIInputTargetImageKey: frame,
                kCIInputTimeKey: w,
            ])
            accumulator = blend?.outputImage ?? acc
        } else {
            accumulator = frame
        }
    }

    /// Finish calibration: store the master and measure its brightness.
    /// Returns true if it looks like a genuine dark (near-black).
    @discardableResult
    func finishCalibration(iso: Float, exposure: Double) -> Bool {
        guard let acc = accumulator else { return false }
        master = acc
        calibratedISO = iso
        calibratedExposure = exposure
        darkMeanLuma = meanLuma(acc)
        // A real dark is nearly black; anything bright means the lens was open.
        isCalibrated = darkMeanLuma < 0.15
        return isCalibrated
    }

    func clear() {
        master = nil
        accumulator = nil
        count = 0
        isCalibrated = false
    }

    /// Subtract the master dark from a light frame (clamped at black).
    func subtract(from light: CIImage) -> CIImage {
        guard let master, isCalibrated else { return light }
        // Align the dark to the light's extent, then subtract.
        let dark = master.cropped(to: light.extent)
        let out = light.applyingFilter("CISubtractBlendMode", parameters: [
            kCIInputBackgroundImageKey: dark,
        ])
        return out
    }

    private func meanLuma(_ image: CIImage) -> Double {
        let e = image.extent
        guard !e.isEmpty, !e.isInfinite else { return 1 }
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: e),
        ]), let out = f.outputImage else { return 1 }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(out, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: nil)
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
