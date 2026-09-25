//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation
import CoreImage

/// **FrameStacker** — a true linear-light running mean of N frames.
///
/// This replaces the app's earlier `CIDissolveTransition`-as-average, which was
/// the core output-quality bug: a dissolve cross-fades in the *display/gamma*
/// space, so it neither computes a real mean nor delivers the √N read-noise drop
/// that stacking exists for. Faint-star signal was crushed and the result stayed
/// muddy no matter how many frames were shot.
///
/// The fix is the standard astrophotography mean, done right:
///   1. work in **linear light** (a CIContext with `workingColorSpace = nil`, so
///      CoreImage does not gamma-encode between ops) — averaging must happen on
///      radiance, not on gamma-companded values;
///   2. keep a **running weighted sum**: `meanₙ = meanₙ₋₁·(n−1)/n + frameₙ·(1/n)`,
///      implemented as two scaled images added together. O(1) memory, one add per
///      frame — cheaper than rebuilding a dissolve graph each time, so it's a
///      performance win as well as a correctness one.
///
/// Averaging N registered frames keeps the (constant) star signal while the
/// (random) read noise falls as 1/√N — the whole point of a stack.
struct FrameStacker {
    private(set) var mean: CIImage?
    private(set) var count = 0

    /// A no-gamma context for realizing the running mean when a caller needs a
    /// concrete image. Shared so we don't spin one up per call.
    static let linearContext = CIContext(options: [.workingColorSpace: NSNull()])

    mutating func reset() {
        mean = nil
        count = 0
    }

    /// Fold one more frame into the running mean. Frames are assumed registered
    /// (same extent, aligned); alignment is the caller's job.
    mutating func add(_ frame: CIImage) {
        count += 1
        guard let prev = mean else {
            mean = frame
            return
        }
        let n = Double(count)
        // meanₙ = prev·(n−1)/n + frame·(1/n), each term a linear scale of the
        // image, summed with additive compositing. Because the working space is
        // linear, the add happens on radiance — a real mean.
        let wPrev = (n - 1.0) / n
        let wNew = 1.0 / n
        let scaledPrev = FrameStacker.scale(prev, by: wPrev)
        let scaledNew = FrameStacker.scale(frame, by: wNew)
        mean = scaledNew.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: scaledPrev,
        ])
    }

    /// Scale an image's RGB by a scalar (alpha left at 1) via CIColorMatrix.
    private static func scale(_ image: CIImage, by k: Double) -> CIImage {
        let v = CGFloat(k)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: v, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: v, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: v, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }
}
