import Foundation
import CoreImage

/// **AutoDevelop** — the editor's on-device intelligence. It looks at the actual
/// captured frame (its brightness histogram) plus the capture metadata (ISO,
/// exposure) and computes the adjustments needed to *reveal the real night sky*
/// — the thing that's impossible to judge from the raw dark frame by eye.
///
/// This came straight from field testing: a long time-lapse frame looks black
/// until you push exposure, and only then can you tell what it captured.
/// AutoDevelop does that push automatically and, in plain language, explains
/// what the shot was and how it was recovered.
///
/// It is **model-free at the core** (deterministic image statistics decide the
/// numbers) with an **optional tiny on-device LLM** that only phrases the
/// explanation — never changes the recovery. Same rule as CaptureAdvisor: the
/// math decides, the LLM (if present) just narrates.
///
/// © Ankur Sinha. Custom CoreImage analysis, no third-party dependencies.
struct AutoDevelop {

    /// What the frame was shot with, if known (from capture settings / EXIF).
    struct CaptureMeta {
        var iso: Double?
        var exposureSeconds: Double?
        var isStacked: Bool = false
        var frameCount: Int = 1
    }

    struct Result {
        let adjustments: ImageAdjustments
        /// Plain-language explanation for the editor.
        let explanation: String
        /// Measured mean luminance 0…1 (how dark the raw frame is).
        let meanLuma: Double
    }

    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Analyze the frame + metadata and produce a recovery.
    static func develop(_ image: CIImage, meta: CaptureMeta = .init()) -> Result {
        let luma = meanLuminance(of: image)

        var adj = ImageAdjustments()
        var reasons: [String] = []

        // The core move: lift a too-dark frame toward a readable sky. Map the
        // measured mean luminance to an exposure push (darker → bigger push).
        // A clear night sky sits around 0.08–0.15 mean; below that we boost.
        if luma < 0.12 {
            let deficit = (0.12 - luma) / 0.12          // 0…1
            adj.exposure = min(2.5, deficit * 3.0)      // up to +2.5 EV
            adj.starBoost = min(0.85, 0.4 + deficit * 0.6)
            adj.shadows = min(0.6, deficit * 0.7)
            reasons.append("the frame was very dark, so exposure was lifted "
                + String(format: "+%.1f EV", adj.exposure))
        } else if luma > 0.5 {
            // Over-bright (light pollution / dawn) — pull it back.
            adj.exposure = -min(1.5, (luma - 0.5) * 3)
            adj.highlights = 0.7
            reasons.append("the sky was washed out, so exposure was pulled back")
        } else {
            adj.starBoost = 0.35
            reasons.append("exposure was close; a gentle star boost was applied")
        }

        // Keep the black point honest so lifted shadows don't gray the sky.
        adj.contrast = 1.08

        // Reason about the capture settings if we have them.
        if let iso = meta.iso, let exp = meta.exposureSeconds {
            let expText = exp >= 1 ? String(format: "%.0fs", exp)
                                   : String(format: "%.0fms", exp * 1000)
            reasons.insert("shot at ISO \(Int(iso)) · \(expText)"
                + (meta.isStacked ? " · \(meta.frameCount) frames stacked" : ""), at: 0)
            if exp < 0.5 && !meta.isStacked {
                reasons.append("that's a short exposure — stacking would pull in "
                    + "more faint stars next time")
            }
        }

        let explanation = reasons.joined(separator: "; ") + "."
        return Result(adjustments: adj, explanation: explanation.prefix(1).uppercased()
                        + explanation.dropFirst(), meanLuma: luma)
    }

    /// Mean luminance of the frame via CIAreaAverage over the whole extent.
    private static func meanLuminance(of image: CIImage) -> Double {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: image,
                  kCIInputExtentKey: CIVector(cgRect: extent),
              ]),
              let output = filter.outputImage else { return 0.1 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ctx.render(output, toBitmap: &bitmap, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: nil)
        // Rec. 709 luma from the averaged pixel.
        let r = Double(bitmap[0]) / 255, g = Double(bitmap[1]) / 255, b = Double(bitmap[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
