import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// An objective focus / star-sharpness score (0–100) from edge acutance. Sharp
/// focus produces strong high-frequency edges (crisp star points); soft focus
/// blurs them away. We run an edge detector, take the mean edge energy, and map
/// it to a friendly score + verdict — so instead of squinting at the preview you
/// get a number telling you if the stars are tack sharp.
///
/// This is a *relative* meter, not a calibrated MTF — but it reliably rises as
/// you dial focus toward the sweet spot, which is exactly what you need in the
/// field.
///
/// © Ankur Sinha.
struct SharpnessScore {
    /// 0…100.
    let value: Int
    /// A plain-language verdict.
    let verdict: String

    var color: SharpnessColor {
        switch value {
        case ..<35:  return .soft
        case ..<70:  return .good
        default:     return .sharp
        }
    }

    enum SharpnessColor { case soft, good, sharp }
}

enum SharpnessComputer {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Compute the score from a CIImage. Downsamples for speed; safe on any size.
    static func score(_ image: CIImage) -> SharpnessScore? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, !extent.isNull else { return nil }

        // Downsample so the metric is fast and resolution-independent.
        let target: CGFloat = 640
        let scale = min(1, target / max(extent.width, extent.height))
        let small = image.transformed(by: .init(scaleX: scale, y: scale)).clampedToExtent()
        let sampleRect = image.extent.applying(.init(scaleX: scale, y: scale))

        // High-pass via a Laplacian 3×3 convolution. A flat region → ~0 energy;
        // crisp edges (in-focus stars) → strong energy. Weights sum to zero so a
        // uniform image genuinely produces zero response.
        let laplacian = CIFilter.convolution3X3()
        laplacian.inputImage = small
        laplacian.weights = CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9)
        laplacian.bias = 0
        guard let hp = laplacian.outputImage else { return nil }

        // Mean absolute response over the interior (avoid the clamped border).
        let interior = sampleRect.insetBy(dx: sampleRect.width * 0.05,
                                          dy: sampleRect.height * 0.05)
        let avg = CIFilter.areaAverage()
        avg.inputImage = hp.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1])
        avg.extent = interior
        guard let out = avg.outputImage else { return nil }

        var px = [Float](repeating: 0, count: 4)
        ctx.render(out, toBitmap: &px, rowBytes: 16,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBAf, colorSpace: nil)
        // Absolute luminance of the mean high-pass response.
        let energy = abs(0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2])

        // Map energy → 0…100 with a log curve tuned so flat ≈ 0 and crisp night
        // detail lands mid-to-high.
        let normalized = min(1.0, max(0.0, Double(log10(1 + energy * 1500)) / 2.4))
        let value = Int((normalized * 100).rounded())

        let verdict: String
        switch value {
        case ..<35:  verdict = "Soft — refine focus"
        case ..<70:  verdict = "Good focus"
        default:     verdict = "Tack sharp"
        }
        return SharpnessScore(value: value, verdict: verdict)
    }
}
