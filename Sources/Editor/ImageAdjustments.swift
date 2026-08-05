import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// The set of edits the post-capture editor can apply. Values are neutral at
/// their defaults, so an untouched photo passes through unchanged.
///
/// © Ankur Sinha. Custom CoreImage pipeline, no third-party dependencies.
struct ImageAdjustments: Equatable {
    var exposure: Double = 0      // EV, −2…+2
    var contrast: Double = 1      // 0.5…1.5 (1 = neutral)
    var brightness: Double = 0    // −0.3…+0.3
    var saturation: Double = 1    // 0…2 (1 = neutral)
    var warmth: Double = 0        // −1…+1 (temperature shift)
    var highlights: Double = 1    // 0.3…1 (pull highlights down)
    var shadows: Double = 0       // 0…1 (lift shadows)
    /// Astro "enhance": a histogram stretch that pulls faint stars out of the
    /// dark — the signature one-tap night boost. 0 = off, 1 = full stretch.
    var starBoost: Double = 0

    static let neutral = ImageAdjustments()
    var isNeutral: Bool { self == .neutral }
}

/// Applies `ImageAdjustments` to a CIImage. Kept as a pure transform so the
/// editor can re-render live on a slider drag and export the same pipeline at
/// full resolution on save.
enum ImageProcessor {

    static func apply(_ adj: ImageAdjustments, to input: CIImage) -> CIImage {
        var image = input

        // Exposure (EV).
        if adj.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(adj.exposure)
            image = f.outputImage ?? image
        }

        // Tone: brightness / contrast / saturation in one pass.
        if adj.brightness != 0 || adj.contrast != 1 || adj.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(adj.brightness)
            f.contrast = Float(adj.contrast)
            f.saturation = Float(adj.saturation)
            image = f.outputImage ?? image
        }

        // Warmth (temperature/tint shift).
        if adj.warmth != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            let shift = 1000 * adj.warmth   // ±1000K around neutral 6500K
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - shift, y: 0)
            image = f.outputImage ?? image
        }

        // Highlights & shadows.
        if adj.highlights != 1 || adj.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.highlightAmount = Float(adj.highlights)
            f.shadowAmount = Float(adj.shadows)
            image = f.outputImage ?? image
        }

        // Star boost: a gamma + tone-curve stretch that lifts faint signal
        // while holding the black point, so stars emerge without graying the sky.
        if adj.starBoost > 0 {
            image = starStretch(image, amount: adj.starBoost)
        }

        return image
    }

    /// The astro histogram stretch. Combines a mild gamma lift with a tone curve
    /// that keeps shadows dark (black sky) and brightens the faint mid-lows where
    /// stars live.
    private static func starStretch(_ input: CIImage, amount: Double) -> CIImage {
        var image = input

        // Gamma < 1 brightens midtones; scale by the amount.
        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = image
        gamma.power = Float(1.0 - 0.45 * amount)   // 1.0 → 0.55
        image = gamma.outputImage ?? image

        // Tone curve: hold the black point, lift low-mids, keep highlights.
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        let lift = Float(0.12 * amount)
        curve.point0 = CGPoint(x: 0.00, y: 0.00)
        curve.point1 = CGPoint(x: 0.25, y: Double(0.25 + lift))
        curve.point2 = CGPoint(x: 0.50, y: Double(0.50 + lift * 0.7))
        curve.point3 = CGPoint(x: 0.75, y: 0.80)
        curve.point4 = CGPoint(x: 1.00, y: 1.00)
        image = curve.outputImage ?? image

        return image
    }
}
