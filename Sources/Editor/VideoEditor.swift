//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

/// Simple video / time-lapse editor: play, **trim** start/end, apply basic
/// brightness / contrast / exposure / saturation (live, per-frame), and export a
/// new video back to Photos. The counterpart to the still `PhotoEditorView`;
/// videos route here, photos route to the photo editor.
///
/// © Ankur Sinha.
struct VideoEditorView: View {
    let url: URL
    let onDone: () -> Void

    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var adjust = VideoAdjust()
    @State private var exporting = false
    @State private var exportProgress: Double = 0
    @State private var status: String?
    @State private var thumbnails: [UIImage] = []
    @State private var draggingStart = false
    @State private var draggingEnd = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer(); ProgressView().tint(.white); Spacer()
                }
                controls
            }
        }
        .onAppear(perform: setup)
        .onDisappear { player?.pause() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button("Discard", role: .destructive) { onDone() }
            Spacer()
            Text("Edit video").font(.headline).foregroundStyle(.white)
            Spacer()
            Button {
                Task { await export() }
            } label: {
                if exporting { Text("\(Int(exportProgress * 100))%").monospacedDigit() }
                else { Text("Export").fontWeight(.semibold) }
            }
            .disabled(exporting)
        }
        .padding()
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(.green)
            }
            trimTimeline
            // Adjust sliders.
            adjustSlider("Exposure", $adjust.exposure, -2, 2)
            adjustSlider("Brightness", $adjust.brightness, -0.3, 0.3)
            adjustSlider("Contrast", $adjust.contrast, 0.5, 1.5)
            adjustSlider("Color", $adjust.saturation, 0, 2)
        }
        .padding()
        .background(.black)
        .onChange(of: adjust) { _, _ in applyLivePreview() }
    }

    // MARK: - Trim timeline (filmstrip + draggable handles)

    private var trimTimeline: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Trim").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.1f–%.1fs (%.1fs)", trimStart, trimEnd, trimEnd - trimStart))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geo in
                let w = geo.size.width
                let startX = duration > 0 ? CGFloat(trimStart / duration) * w : 0
                let endX = duration > 0 ? CGFloat(trimEnd / duration) * w : w
                ZStack(alignment: .leading) {
                    // Filmstrip thumbnails.
                    HStack(spacing: 0) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: w / CGFloat(max(1, thumbnails.count)), height: 48)
                                .clipped()
                        }
                    }
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Dim the trimmed-out regions.
                    Color.black.opacity(0.55).frame(width: startX)
                    Color.black.opacity(0.55).frame(width: max(0, w - endX)).offset(x: endX)

                    // Selected window border.
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: max(0, endX - startX), height: 48).offset(x: startX)

                    // Handles.
                    handle.offset(x: startX - 6)
                        .gesture(DragGesture().onChanged { g in
                            let t = Double(max(0, min(g.location.x, endX - 12)) / w) * duration
                            trimStart = min(t, trimEnd - 0.2); seek(trimStart)
                        })
                    handle.offset(x: endX - 6)
                        .gesture(DragGesture().onChanged { g in
                            let t = Double(min(w, max(g.location.x, startX + 12)) / w) * duration
                            trimEnd = max(t, trimStart + 0.2); seek(trimEnd)
                        })
                }
            }
            .frame(height: 48)
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.yellow)
            .frame(width: 12, height: 52)
            .overlay(Image(systemName: "line.3.horizontal").font(.system(size: 8)).foregroundStyle(.black))
    }

    private func adjustSlider(_ label: String, _ value: Binding<Double>, _ lo: Double, _ hi: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).frame(width: 70, alignment: .leading)
            Slider(value: value, in: lo...hi).tint(.white)
        }
    }

    // MARK: - Setup + preview

    private func setup() {
        let asset = AVURLAsset(url: url)
        Task {
            let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            await MainActor.run {
                duration = dur
                trimStart = 0
                trimEnd = dur
                let item = AVPlayerItem(asset: asset)
                item.videoComposition = VideoAdjust.composition(for: asset, adjust: adjust)
                let p = AVPlayer(playerItem: item)
                p.isMuted = true
                player = p
                p.play()
            }
            await generateThumbnails(asset: asset, duration: dur)
        }
    }

    /// Build a filmstrip of ~10 evenly-spaced thumbnails for the trim timeline.
    private func generateThumbnails(asset: AVAsset, duration: Double) async {
        guard duration > 0 else { return }
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 160, height: 160)
        g.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        g.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let count = 10
        var thumbs: [UIImage] = []
        for i in 0..<count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            if let cg = try? await withCheckedThrowingContinuation({ (cont: CheckedContinuation<CGImage, Error>) in
                g.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: t, preferredTimescale: 600))]) { _, image, _, _, err in
                    if let image { cont.resume(returning: image) } else { cont.resume(throwing: err ?? CocoaError(.featureUnsupported)) }
                }
            }) {
                thumbs.append(UIImage(cgImage: cg))
            }
        }
        let final = thumbs
        await MainActor.run { thumbnails = final }
    }

    private func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }

    /// Rebuild the composition so the preview reflects the current adjustments.
    private func applyLivePreview() {
        guard let item = player?.currentItem else { return }
        item.videoComposition = VideoAdjust.composition(for: item.asset, adjust: adjust)
    }

    // MARK: - Export

    private func export() async {
        await MainActor.run { exporting = true; exportProgress = 0; status = nil }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            await MainActor.run { status = "Export unavailable"; exporting = false }
            return
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("firmament-\(UUID().uuidString).mov")
        export.outputURL = out
        export.outputFileType = .mov
        export.videoComposition = VideoAdjust.composition(for: asset, adjust: adjust)
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600))

        // Progress ticker.
        let ticker = Task { @MainActor in
            while !Task.isCancelled && export.status == .exporting {
                exportProgress = Double(export.progress)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await export.export()
        ticker.cancel()

        if export.status == .completed {
            let ok = await saveVideo(out)
            await MainActor.run {
                exporting = false
                status = ok ? "Saved to Photos" : "Save failed"
            }
        } else {
            await MainActor.run {
                exporting = false
                status = export.error?.localizedDescription ?? "Export failed"
            }
        }
    }

    private func saveVideo(_ url: URL) async -> Bool {
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch { return false }
    }
}

/// The adjustable parameters for the video editor.
struct VideoAdjust: Equatable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1

    var isNeutral: Bool {
        exposure == 0 && brightness == 0 && contrast == 1 && saturation == 1
    }

    /// Build an AVVideoComposition that applies these adjustments per frame.
    static func composition(for asset: AVAsset, adjust: VideoAdjust) -> AVVideoComposition? {
        if adjust.isNeutral { return nil }
        return AVVideoComposition(asset: asset) { request in
            var image = request.sourceImage.clampedToExtent()
            if adjust.exposure != 0 {
                let f = CIFilter.exposureAdjust(); f.inputImage = image
                f.ev = Float(adjust.exposure); image = f.outputImage ?? image
            }
            if adjust.brightness != 0 || adjust.contrast != 1 || adjust.saturation != 1 {
                let f = CIFilter.colorControls(); f.inputImage = image
                f.brightness = Float(adjust.brightness)
                f.contrast = Float(adjust.contrast)
                f.saturation = Float(adjust.saturation)
                image = f.outputImage ?? image
            }
            request.finish(with: image.cropped(to: request.sourceImage.extent), context: nil)
        }
    }
}
