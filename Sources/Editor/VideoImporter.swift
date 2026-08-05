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

    /// Sample up to `maxFrames` frames evenly across the clip and average them.
    func stackedFrame(from url: URL, maxFrames: Int = 24) async -> CIImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return await singleFrame(from: asset)
        }
        let total = CMTimeGetSeconds(duration)
        guard total > 0 else { return await singleFrame(from: asset) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true   // correct orientation
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let count = min(maxFrames, max(1, Int(total)))
        var times: [NSValue] = []
        for i in 0..<count {
            let t = total * (Double(i) + 0.5) / Double(count)
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
        }

        // Accumulate an average via progressive blend.
        var accumulator: CIImage?
        var n = 0
        for value in times {
            guard let cg = try? await imageCG(generator, at: value.timeValue) else { continue }
            let frame = CIImage(cgImage: cg)
            n += 1
            if let acc = accumulator {
                let w = 1.0 / Double(n)
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
        guard let acc = accumulator,
              let cg = ctx.createCGImage(acc, from: acc.extent) else {
            return await singleFrame(from: asset)
        }
        return CIImage(cgImage: cg)
    }

    private func singleFrame(from asset: AVAsset) async -> CIImage? {
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        guard let cg = try? await imageCG(g, at: CMTime(seconds: 0.5, preferredTimescale: 600)) else {
            return nil
        }
        return CIImage(cgImage: cg)
    }

    /// async wrapper around the image generator.
    private func imageCG(_ g: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            g.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                if let image { cont.resume(returning: image) }
                else { cont.resume(throwing: error ?? CocoaError(.featureUnsupported)) }
            }
        }
    }
}
