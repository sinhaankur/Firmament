//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import SwiftUI
import UIKit
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
    @State private var activeFilter: VideoFilter = .none

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let player {
                    GeometryReader { geo in
                        ZStack {
                            VideoPlayer(player: player)
                            // Live draggable caption preview.
                            if !adjust.overlay.isEmpty {
                                Text(adjust.overlay.text)
                                    .font(.system(size: max(10, geo.size.height * adjust.overlay.sizeFraction), weight: .semibold))
                                    .foregroundStyle(overlayColor)
                                    .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                                    .position(x: adjust.overlay.xNorm * geo.size.width,
                                              y: adjust.overlay.yNorm * geo.size.height)
                                    .gesture(DragGesture().onChanged { g in
                                        adjust.overlay.xNorm = min(1, max(0, g.location.x / geo.size.width))
                                        adjust.overlay.yNorm = min(1, max(0, g.location.y / geo.size.height))
                                    })
                            }
                        }
                    }
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
            filterRow
            textPanel
            // Adjust sliders.
            adjustSlider("Exposure", $adjust.exposure, -2, 2)
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

    // MARK: - Filter row (one-tap looks)

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VideoFilter.allCases) { f in
                    Button { Theme.tap(); applyFilter(f) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: f.icon).font(.system(size: 15))
                            Text(f.rawValue).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .frame(width: 66, height: 46)
                        .background(activeFilter == f ? Color.white.opacity(0.2) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(activeFilter == f ? (f == .nightRecover ? .yellow : Theme.accent) : .clear, lineWidth: 1.5))
                        .foregroundStyle(f == .nightRecover ? .yellow : .white)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Apply a filter as the new base — but keep any text overlay the user added.
    private func applyFilter(_ f: VideoFilter) {
        activeFilter = f
        let keptOverlay = adjust.overlay
        adjust = f.base
        adjust.overlay = keptOverlay
    }

    // MARK: - Text / caption panel

    private var overlayColor: Color {
        let i = adjust.overlay.colorIndex
        let c = i < TextOverlay.palette.count ? TextOverlay.palette[i].ci : TextOverlay.palette[0].ci
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var textPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "textformat").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                TextField("Add a caption…", text: $adjust.overlay.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            if !adjust.overlay.isEmpty {
                HStack(spacing: 10) {
                    // Color chips.
                    ForEach(Array(TextOverlay.palette.enumerated()), id: \.offset) { i, entry in
                        Button { adjust.overlay.colorIndex = i } label: {
                            Circle()
                                .fill(Color(red: entry.ci.red, green: entry.ci.green, blue: entry.ci.blue))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.white, lineWidth: adjust.overlay.colorIndex == i ? 2 : 0))
                                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                    Divider().frame(height: 16).overlay(.white.opacity(0.2))
                    Image(systemName: "textformat.size").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Slider(value: $adjust.overlay.sizeFraction, in: 0.03...0.15).tint(.white)
                }
                Text("Drag the caption on the video to place it.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
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
                Theme.notify(ok ? .success : .error)
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

/// One-tap video looks. "Night Recover" is Firmament's signature — it lifts a
/// dark timelapse and strips light-pollution glow, as a video. No other video
/// editor has that.
enum VideoFilter: String, CaseIterable, Identifiable {
    case none = "None"
    case nightRecover = "Night Recover"
    case vivid = "Vivid"
    case cool = "Cool"
    case warm = "Warm"
    case mono = "Mono"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .nightRecover: return "sparkles"
        case .vivid: return "camera.filters"
        case .cool: return "snowflake"
        case .warm: return "sun.max"
        case .mono: return "circle.lefthalf.filled"
        }
    }

    /// The base adjustment this filter applies (the user can still tweak on top).
    var base: VideoAdjust {
        switch self {
        case .none:          return VideoAdjust()
        case .nightRecover:  return VideoAdjust(exposure: 1.1, contrast: 1.08, saturation: 1.1, dehaze: 0.5, vibrance: 0.3)
        case .vivid:         return VideoAdjust(contrast: 1.1, saturation: 1.15, vibrance: 0.5)
        case .cool:          return VideoAdjust(saturation: 1.05, warmth: -0.5)
        case .warm:          return VideoAdjust(saturation: 1.05, warmth: 0.5)
        case .mono:          return VideoAdjust(contrast: 1.1, saturation: 0)
        }
    }
}

/// A text overlay burned into the video. Position is normalized (0…1) from the
/// top-left of the frame; size is a fraction of the frame height.
struct TextOverlay: Equatable {
    var text: String = ""
    var xNorm: Double = 0.5
    var yNorm: Double = 0.85
    var sizeFraction: Double = 0.06   // ~6% of frame height
    var colorIndex: Int = 0           // into TextOverlay.palette

    static let palette: [(name: String, ci: CIColor)] = [
        ("White", CIColor(red: 1, green: 1, blue: 1)),
        ("Yellow", CIColor(red: 1, green: 0.85, blue: 0.2)),
        ("Cyan", CIColor(red: 0.4, green: 0.85, blue: 1)),
        ("Black", CIColor(red: 0, green: 0, blue: 0)),
    ]
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// The adjustable parameters for the video editor.
struct VideoAdjust: Equatable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var dehaze: Double = 0      // light-pollution / glow removal
    var vibrance: Double = 0
    var warmth: Double = 0      // −1 cool … +1 warm
    var overlay = TextOverlay()

    var isNeutral: Bool {
        exposure == 0 && brightness == 0 && contrast == 1 && saturation == 1
        && dehaze == 0 && vibrance == 0 && warmth == 0 && overlay.isEmpty
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
            if adjust.dehaze > 0 {
                // Cool the skyglow cast + re-anchor black (same idea as the photo
                // editor's De-glow), matrix-only for per-frame speed.
                let m = CIFilter.colorMatrix(); m.inputImage = image
                let a = adjust.dehaze
                m.rVector = CIVector(x: CGFloat(1 - 0.06 * a), y: 0, z: 0, w: 0)
                m.gVector = CIVector(x: 0, y: CGFloat(1 - 0.03 * a), z: 0, w: 0)
                m.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
                m.biasVector = CIVector(x: CGFloat(-0.03 * a), y: CGFloat(-0.03 * a), z: CGFloat(-0.02 * a), w: 0)
                image = m.outputImage ?? image
            }
            if adjust.warmth != 0 {
                let f = CIFilter.temperatureAndTint(); f.inputImage = image
                f.neutral = CIVector(x: 6500, y: 0)
                f.targetNeutral = CIVector(x: 6500 - 1000 * adjust.warmth, y: 0)
                image = f.outputImage ?? image
            }
            if adjust.brightness != 0 || adjust.contrast != 1 || adjust.saturation != 1 {
                let f = CIFilter.colorControls(); f.inputImage = image
                f.brightness = Float(adjust.brightness)
                f.contrast = Float(adjust.contrast)
                f.saturation = Float(adjust.saturation)
                image = f.outputImage ?? image
            }
            if adjust.vibrance != 0 {
                let f = CIFilter.vibrance(); f.inputImage = image
                f.amount = Float(adjust.vibrance); image = f.outputImage ?? image
            }
            // Text overlay, composited over the graded frame.
            if !adjust.overlay.isEmpty {
                if let text = Self.renderText(adjust.overlay, in: request.sourceImage.extent) {
                    image = text.composited(over: image)
                }
            }
            request.finish(with: image.cropped(to: request.sourceImage.extent), context: nil)
        }
    }

    /// Render the caption to a transparent CIImage sized to the frame, with a
    /// soft shadow so it reads over the sky.
    static func renderText(_ overlay: TextOverlay, in extent: CGRect) -> CIImage? {
        guard !overlay.isEmpty else { return nil }
        let w = extent.width, h = extent.height
        guard w > 0, h > 0 else { return nil }
        let fontSize = max(8, h * CGFloat(overlay.sizeFraction))

        let color = overlay.colorIndex < TextOverlay.palette.count
            ? TextOverlay.palette[overlay.colorIndex].ci : TextOverlay.palette[0].ci
        let uiColor = UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: uiColor,
            .shadow: {
                let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.8)
                s.shadowBlurRadius = fontSize * 0.15; s.shadowOffset = .init(width: 0, height: 1); return s
            }(),
        ]
        let string = NSAttributedString(string: overlay.text, attributes: attrs)
        let textSize = string.size()

        // Render at scale 1 so the CIImage extent matches the video frame's
        // pixel extent exactly (no retina 3× mismatch when compositing).
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt)
        let img = renderer.image { _ in
            // Draw centered at the normalized position (UIKit y is top-down).
            let x = CGFloat(overlay.xNorm) * w - textSize.width / 2
            let y = CGFloat(overlay.yNorm) * h - textSize.height / 2
            string.draw(at: CGPoint(x: x, y: y))
        }
        guard let cg = img.cgImage else { return nil }
        // CoreImage's y is bottom-up; flip so text lands where the user placed it.
        return CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }
}
