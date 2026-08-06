import Foundation
import AVFoundation
import CoreImage
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

/// Turns a picked video / time-lapse into a single still the editor can develop.
/// It samples frames across the clip and **averages** them — the same stacking
/// idea as live capture: a dark time-lapse becomes one brighter, lower-noise
/// frame that AutoDevelop can then recover. If averaging isn't possible it falls
/// back to a single representative frame.
///
/// © Ankur Sinha.
struct VideoImporter {

    /// A transferable movie file from PhotosPicker.
    struct Movie: Transferable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                // Copy out of the temporary location so it survives the call.
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mov")
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: received.file, to: dst)
                return Movie(url: dst)
            }
        }
    }

    private let ctx = CIContext()

    /// Sample a few frames evenly across the clip and average them into one
    /// brighter still. Kept deliberately light so it can't hang the import:
    ///   • **8 frames max** (24 was slow enough to look frozen on a 4K clip),
    ///   • **downsampled** via `maximumSize` so decoding is fast,
    ///   • **relaxed time tolerance** (exact-frame seeking is far slower),
    ///   • a hard **overall timeout** — if the video is huge or still in iCloud,
    ///     we return whatever we have rather than spinning forever.
    func stackedFrame(from url: URL, maxFrames: Int = 8) async -> CIImage? {
        await withTimeout(seconds: 12) { [self] in
            await stack(url: url, maxFrames: maxFrames)
        }
    }

    private func stack(url: URL, maxFrames: Int) async -> CIImage? {
        let asset = AVURLAsset(url: url)
        let total = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true          // correct orientation
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 2400, height: 2400) // downsample for speed

        guard total > 0 else {
            // No duration (odd file) — just grab one frame near the start.
            return (try? await frame(generator, at: CMTime(seconds: 0.1, preferredTimescale: 600)))
                .map { CIImage(cgImage: $0) }
        }

        let count = min(maxFrames, max(1, Int(total)))
        var accumulator: CIImage?
        var n = 0
        for i in 0..<count {
            let t = total * (Double(i) + 0.5) / Double(count)
            guard let cg = try? await frame(generator, at: CMTime(seconds: t, preferredTimescale: 600)) else { continue }
            let img = CIImage(cgImage: cg)
            n += 1
            if let acc = accumulator {
                let blend = CIFilter(name: "CIDissolveTransition", parameters: [
                    kCIInputImageKey: acc,
                    kCIInputTargetImageKey: img,
                    kCIInputTimeKey: 1.0 / Double(n),
                ])
                accumulator = blend?.outputImage ?? acc
            } else {
                accumulator = img
            }
        }
        guard let acc = accumulator, let cg = ctx.createCGImage(acc, from: acc.extent) else { return nil }
        return CIImage(cgImage: cg)
    }

    /// Single-frame extraction with a guaranteed one-shot continuation (the
    /// handler fires once per requested time; we resume exactly once).
    private func frame(_ g: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            g.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                if let image { cont.resume(returning: image) }
                else { cont.resume(throwing: error ?? CocoaError(.featureUnsupported)) }
            }
        }
    }

    /// Run an async operation with a hard timeout; returns nil if it overruns.
    private func withTimeout(seconds: Double, _ op: @escaping () async -> CIImage?) async -> CIImage? {
        await withTaskGroup(of: CIImage?.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
