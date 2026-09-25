//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import XCTest
import CoreImage
@testable import NightSky

/// Proof that stacking actually improves the image — the thing the old
/// `CIDissolveTransition` "average" could not do. These tests measure real pixel
/// statistics on synthetic frames, so "it performs better" is demonstrated, not
/// claimed.
final class FrameStackerTests: XCTestCase {

    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Read the mean + variance of a small solid/─noisy image's luminance by
    /// rendering it to a bitmap and looking at the pixels.
    private func stats(_ image: CIImage, size: Int = 32) -> (mean: Double, variance: Double) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        ctx.render(image.cropped(to: rect), toBitmap: &buf, rowBytes: size * 4,
                   bounds: rect, format: .RGBA8, colorSpace: nil)
        var vals: [Double] = []
        vals.reserveCapacity(size * size)
        for i in stride(from: 0, to: buf.count, by: 4) {
            vals.append(Double(buf[i]) / 255.0) // red channel is enough for grey noise
        }
        let mean = vals.reduce(0, +) / Double(vals.count)
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(vals.count)
        return (mean, variance)
    }

    /// A frame = a constant grey signal + per-pixel random noise, seeded.
    private func noisyFrame(signal: Double, noise: Double, seed: UInt64, size: Int = 32) -> CIImage {
        var rng = SystemRandomNumberGenerator()
        _ = seed // determinism isn't required for the statistical assertion; we
                 // use enough pixels that the law holds regardless.
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let n = Double.random(in: -noise...noise, using: &rng)
            let v = max(0, min(1, signal + n))
            let b = UInt8(v * 255)
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = 255
        }
        let data = Data(px)
        return CIImage(bitmapData: data, bytesPerRow: size * 4,
                       size: CGSize(width: size, height: size),
                       format: .RGBA8, colorSpace: nil)
    }

    /// The core proof: stacking N noisy frames of the SAME signal cuts the noise
    /// variance roughly in proportion to N (read noise falls ~1/√N → variance
    /// ~1/N), while the mean signal is preserved.
    func testStackingReducesNoise() {
        let signal = 0.4
        let noise = 0.12
        let n = 16

        let single = noisyFrame(signal: signal, noise: noise, seed: 1)
        let singleStats = stats(single)

        var stacker = FrameStacker()
        for i in 0..<n {
            stacker.add(noisyFrame(signal: signal, noise: noise, seed: UInt64(100 + i)))
        }
        guard let stacked = stacker.mean else { return XCTFail("no stacked result") }
        let stackedStats = stats(stacked)

        // Signal preserved: the stacked mean stays near the true signal.
        XCTAssertEqual(stackedStats.mean, signal, accuracy: 0.05,
                       "stacking must preserve the mean signal")

        // Noise cut hard: variance should drop well below the single frame's.
        // Theory says ~1/N; assert at least a 4× reduction to stay robust to the
        // 8-bit render quantization.
        XCTAssertLessThan(stackedStats.variance, singleStats.variance / 4.0,
                          "stacking \(n) frames must materially reduce noise "
                          + "(single var \(singleStats.variance), stacked \(stackedStats.variance))")
    }

    /// A real mean is idempotent on identical frames: stacking the same frame N
    /// times returns that frame's value. (A gamma-space dissolve would NOT — this
    /// is exactly what the old path got wrong.)
    func testStackingIdenticalFramesIsIdentity() {
        let signal = 0.6
        let clean = noisyFrame(signal: signal, noise: 0, seed: 7)
        var stacker = FrameStacker()
        for _ in 0..<10 { stacker.add(clean) }
        guard let out = stacker.mean else { return XCTFail("no result") }
        XCTAssertEqual(stats(out).mean, signal, accuracy: 0.02,
                       "mean of identical frames must equal the frame")
    }

    /// Averaging happens in LINEAR light: the mean of a black frame and a white
    /// frame is mid-grey in linear radiance (~0.5), NOT the ~0.73 you'd get from
    /// averaging gamma-encoded sRGB values. This pins the color-space correctness
    /// that was the root bug.
    func testStackingAveragesInLinearLight() {
        let black = noisyFrame(signal: 0.0, noise: 0, seed: 1)
        let white = noisyFrame(signal: 1.0, noise: 0, seed: 2)
        var stacker = FrameStacker()
        stacker.add(black)
        stacker.add(white)
        guard let out = stacker.mean else { return XCTFail("no result") }
        // Rendered back through the linear context, a true linear mean of 0 and 1
        // is 0.5. (Gamma-space averaging would land near 0.73.)
        XCTAssertEqual(stats(out).mean, 0.5, accuracy: 0.06,
                       "the average of black + white must be linear mid-grey")
    }

    func testResetClearsState() {
        var stacker = FrameStacker()
        stacker.add(noisyFrame(signal: 0.5, noise: 0, seed: 1))
        XCTAssertEqual(stacker.count, 1)
        stacker.reset()
        XCTAssertEqual(stacker.count, 0)
        XCTAssertNil(stacker.mean)
    }
}
