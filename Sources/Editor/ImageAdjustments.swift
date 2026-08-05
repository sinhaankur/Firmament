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
    /// Light-pollution / haze removal: lifts the black point off the orange
    /// skyglow and cools the cast. 0 = off, 1 = strong. The biggest quality win
    /// for city shots.
    var dehaze: Double = 0
    /// Vibrance: saturates muted colours while protecting already-saturated
    /// ones — nebula/aurora colour without going garish. 0 = neutral.
    var vibrance: Double = 0

    /// Geometry: rotation, straighten, and crop. Applied before tonal edits.
    var geometry = Geometry()

    static let neutral = ImageAdjustments()
    var isNeutral: Bool { self == .neutral }
}

/// Crop / rotate / straighten. Non-destructive: stored as parameters and applied
/// in the pipeline, so it stays editable until save.
struct Geometry: Equatable {
    /// 90° rotations, 0…3 (clockwise).
    var quarterTurns: Int = 0
    /// Fine straighten angle in degrees, −15…+15 (levels the horizon).
    var straightenDegrees: Double = 0
    /// Crop rectangle in *normalized* coordinates of the rotated image
    /// (0…1, origin bottom-left to match CoreImage). Full frame by default.
    var cropNormalized: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var isIdentity: Bool {
        quarterTurns == 0 && straightenDegrees == 0 &&
        cropNormalized == CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

/// Applies `ImageAdjustments` to a CIImage. Kept as a pure transform so the
/// editor can re-render live on a slider drag and export the same pipeline at
/// full resolution on save.
enum ImageProcessor {

    static func apply(_ adj: ImageAdjustments, to input: CIImage) -> CIImage {
        var image = input

        // Geometry first (rotate / straighten / crop), so everything downstream
        // — histogram, tonal edits, save — sees the framed image.
        if !adj.geometry.isIdentity {
            image = applyGeometry(adj.geometry, to: image)
        }

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

        // Light-pollution / haze removal: subtract a warm skyglow cast and lift
        // the black point off it, so the sky goes deep instead of orange-grey.
        if adj.dehaze > 0 {
            image = removeSkyglow(image, amount: adj.dehaze)
        }

        // Vibrance: boost muted colours, protect already-saturated ones.
        if adj.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(adj.vibrance)
            image = f.outputImage ?? image
        }

        // Star boost: a gamma + tone-curve stretch that lifts faint signal
        // while holding the black point, so stars emerge without graying the sky.
        if adj.starBoost > 0 {
            image = starStretch(image, amount: adj.starBoost)
        }

        return image
    }

    /// Apply rotation, straighten, and crop. Order: 90° turns → fine straighten
    /// rotation about the centre → crop (normalized rect of the rotated image).
    /// The result is re-origined to (0,0) so downstream extents behave.
    static func applyGeometry(_ g: Geometry, to input: CIImage) -> CIImage {
        var image = input

        // 90° turns.
        if g.quarterTurns % 4 != 0 {
            let angle = -CGFloat(g.quarterTurns % 4) * .pi / 2   // clockwise
            image = image.transformed(by: CGAffineTransform(rotationAngle: angle))
            image = image.transformed(by: CGAffineTransform(
                translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }

        // Fine straighten (rotate about centre, then re-origin).
        if g.straightenDegrees != 0 {
            let a = CGFloat(-g.straightenDegrees * .pi / 180)
            let c = CGPoint(x: image.extent.midX, y: image.extent.midY)
            var t = CGAffineTransform(translationX: c.x, y: c.y)
            t = t.rotated(by: a)
            t = t.translatedBy(x: -c.x, y: -c.y)
            image = image.transformed(by: t)
            image = image.transformed(by: CGAffineTransform(
                translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }

        // Crop (normalized rect → pixels of the current extent).
        let e = image.extent
        if g.cropNormalized != CGRect(x: 0, y: 0, width: 1, height: 1),
           !e.isInfinite, !e.isEmpty {
            let rect = CGRect(
                x: e.origin.x + g.cropNormalized.origin.x * e.width,
                y: e.origin.y + g.cropNormalized.origin.y * e.height,
                width: g.cropNormalized.width * e.width,
                height: g.cropNormalized.height * e.height)
            image = image.cropped(to: rect)
            image = image.transformed(by: CGAffineTransform(
                translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }

        return image
    }

    /// Subtract the orange/green skyglow cast and pull the black point down.
    /// A colour-matrix bias removes a warm tint; a tone curve re-anchors black.
    private static func removeSkyglow(_ input: CIImage, amount: Double) -> CIImage {
        var image = input
        let a = Float(amount)

        // Cool the cast: reduce red/green bias typical of sodium/LED skyglow.
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: CGFloat(1 - 0.06 * Double(a)), y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: CGFloat(1 - 0.03 * Double(a)), z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        matrix.biasVector = CIVector(x: CGFloat(-0.03 * Double(a)),
                                     y: CGFloat(-0.03 * Double(a)),
                                     z: CGFloat(-0.02 * Double(a)), w: 0)
        image = matrix.outputImage ?? image

        // Re-anchor black: pull the low end down so the sky reads deep.
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        let lift = CGFloat(0.10 * Double(a))
        curve.point0 = CGPoint(x: 0.00, y: 0.00)
        curve.point1 = CGPoint(x: 0.15 + lift, y: 0.05)
        curve.point2 = CGPoint(x: 0.50, y: 0.50)
        curve.point3 = CGPoint(x: 0.75, y: 0.78)
        curve.point4 = CGPoint(x: 1.00, y: 1.00)
        image = curve.outputImage ?? image
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
