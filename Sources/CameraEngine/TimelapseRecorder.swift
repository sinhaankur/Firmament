import Foundation
import AVFoundation
import CoreImage
import UIKit
import Photos

/// Records a night-sky time-lapse: it captures a frame every `interval` seconds
/// (each frame using the full Night Capture pipeline — long exposure + stacking)
/// and assembles them into a high-quality video written with `AVAssetWriter`.
///
/// "Best configuration on this phone": HEVC at the sensor's full still
/// resolution, the highest quality bitrate, and each frame captured at the
/// device's exposure/ISO ceiling. On a tripod this yields a real astro
/// time-lapse (star trails, the Moon tracking, satellites streaking).
///
/// © Ankur Sinha.
@MainActor
final class TimelapseRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(framesDone: Int, total: Int)
        case assembling
        case saved
        case failed(String)
    }

    @Published var state: State = .idle
    /// Seconds between captured frames.
    @Published var interval: Double = 3
    /// How many frames to capture.
    @Published var frameCount: Int = 120       // ~ default; UI adjusts
    /// Playback frames-per-second of the finished video.
    @Published var outputFPS: Int32 = 24

    private weak var night: NightCapture?
    private var frames: [CGImage] = []
    private var timer: Timer?
    private var captured = 0

    func configure(night: NightCapture) { self.night = night }

    var isRecording: Bool { if case .recording = state { return true }; return false }

    /// Estimated real-world duration of the shoot.
    var estimatedDurationText: String {
        let secs = Double(frameCount) * interval
        return secs >= 60 ? String(format: "%.0f min", secs / 60) : String(format: "%.0f s", secs)
    }

    // MARK: - Recording

    func start() {
        guard let night, !isRecording else { return }
        frames.removeAll()
        captured = 0
        state = .recording(framesDone: 0, total: frameCount)

        // Each tick, grab one developed frame from the capture pipeline.
        night.onFrameForTimelapse = { [weak self] cg in
            Task { @MainActor in self?.appendFrame(cg) }
        }
        fireOne()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fireOne() }
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        night?.onFrameForTimelapse = nil
        state = .idle
        frames.removeAll()
    }

    private func fireOne() {
        guard captured < frameCount else { finish(); return }
        night?.captureTimelapseFrame()
    }

    private func appendFrame(_ cg: CGImage) {
        frames.append(cg)
        captured += 1
        state = .recording(framesDone: captured, total: frameCount)
        if captured >= frameCount { finish() }
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        night?.onFrameForTimelapse = nil
        guard !frames.isEmpty else { state = .failed("No frames captured"); return }
        state = .assembling
        Task { await assemble() }
    }

    // MARK: - Assembly (AVAssetWriter, best quality)

    private func assemble() async {
        let size = CGSize(width: frames[0].width, height: frames[0].height)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("firmament-timelapse-\(UUID().uuidString).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            state = .failed("Writer init failed"); return
        }

        // HEVC, full resolution, high-quality bitrate.
        let bitrate = Int(size.width * size.height) * 12   // generous for detail
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoQualityKey: 1.0,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        guard writer.canAdd(input) else { state = .failed("Cannot add input"); return }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: outputFPS)
        for (i, cg) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 10_000_000) }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: cg, pool: pool) else { continue }
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .completed {
            await saveToPhotos(url)
        } else {
            state = .failed(writer.error?.localizedDescription ?? "Assembly failed")
        }
    }

    private func pixelBuffer(from cg: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return buffer
    }

    private func saveToPhotos(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            state = .failed("Photos access denied"); return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            state = .saved
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
