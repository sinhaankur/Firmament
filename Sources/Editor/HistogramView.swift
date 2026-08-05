import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// A live luminance + RGB histogram — how a photographer judges exposure and
/// clipping. Computed with `CIAreaHistogram` over a downsampled frame and drawn
/// as a compact Canvas. For the night sky the story is at the *left* (the black
/// point): you want the histogram lifted off the wall without crushing shadows.
///
/// © Ankur Sinha.
struct HistogramView: View {
    /// 256-bin normalized channels (0…1 height each).
    let r: [CGFloat]
    let g: [CGFloat]
    let b: [CGFloat]

    var body: some View {
        Canvas { ctx, size in
            guard !r.isEmpty else { return }
            let n = r.count
            let w = size.width / CGFloat(n)
            // Backdrop.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(.black.opacity(0.35)))
            // Draw each channel as an additive translucent curve.
            drawChannel(r, in: ctx, size: size, w: w, color: .red)
            drawChannel(g, in: ctx, size: size, w: w, color: .green)
            drawChannel(b, in: ctx, size: size, w: w, color: .blue)
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
    }

    private func drawChannel(_ data: [CGFloat], in ctx: GraphicsContext,
                             size: CGSize, w: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) * w
            let y = size.height * (1 - v)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.opacity(0.5)))
    }
}

/// Computes a normalized RGB histogram from a CIImage.
enum HistogramComputer {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Returns 64-bin R/G/B arrays normalized to 0…1. Downsamples first so it's
    /// cheap enough to recompute as sliders move.
    static func compute(_ image: CIImage, bins: Int = 64) -> (r: [CGFloat], g: [CGFloat], b: [CGFloat])? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, !extent.isNull else { return nil }

        let filter = CIFilter.areaHistogram()
        filter.inputImage = image
        filter.extent = extent
        filter.count = bins
        filter.scale = 20
        guard let output = filter.outputImage else { return nil }

        // The histogram image is `bins` wide, 1 tall, RGBA float.
        var buffer = [Float](repeating: 0, count: bins * 4)
        ctx.render(output,
                   toBitmap: &buffer,
                   rowBytes: bins * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: bins, height: 1),
                   format: .RGBAf, colorSpace: nil)

        var rArr = [CGFloat](repeating: 0, count: bins)
        var gArr = [CGFloat](repeating: 0, count: bins)
        var bArr = [CGFloat](repeating: 0, count: bins)
        var maxV: Float = 0.0001
        for i in 0..<bins {
            let r = buffer[i * 4], g = buffer[i * 4 + 1], b = buffer[i * 4 + 2]
            rArr[i] = CGFloat(r); gArr[i] = CGFloat(g); bArr[i] = CGFloat(b)
            maxV = max(maxV, r, g, b)
        }
        // Normalize (log-ish so faint star counts are visible).
        for i in 0..<bins {
            rArr[i] = normalize(rArr[i], maxV)
            gArr[i] = normalize(gArr[i], maxV)
            bArr[i] = normalize(bArr[i], maxV)
        }
        return (rArr, gArr, bArr)
    }

    private static func normalize(_ v: CGFloat, _ maxV: Float) -> CGFloat {
        let x = v / CGFloat(maxV)
        // A gentle sqrt keeps the sparse star counts readable next to the sky.
        return min(1, sqrt(x))
    }
}
