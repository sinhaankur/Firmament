import SwiftUI
import CoreImage
import Photos

/// Post-capture review + edit. Opens right after a shot: shows the frame, offers
/// live adjustments (including the one-tap astro "Enhance"), and saves the
/// edited version to Photos. Live preview downsamples for smooth sliders and
/// re-renders the pipeline at full resolution on save.
///
/// © Ankur Sinha.
struct PhotoEditorView: View {
    let original: CIImage
    /// What the frame was captured with (ISO/exposure/stack), if known.
    var meta: AutoDevelop.CaptureMeta = .init()
    let onDone: () -> Void

    @State private var adj = ImageAdjustments()
    @State private var previewImage: UIImage?
    @State private var saving = false
    @State private var savedOK: Bool?
    @State private var activeTool: Tool = .enhance
    @State private var autoExplanation: String?
    @State private var histogram: (r: [CGFloat], g: [CGFloat], b: [CGFloat])?
    @State private var originalPreview: UIImage?   // for before/after compare
    @State private var showingOriginal = false
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var showCrop = false

    private let ctx = CIContext()

    enum Tool: String, CaseIterable {
        case enhance = "Enhance", exposure = "Exposure", contrast = "Contrast"
        case dehaze = "De-glow", highlights = "Highlights", shadows = "Shadows"
        case warmth = "Warmth", saturation = "Color", vibrance = "Vibrance"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()   // fully cover the camera behind us
            VStack(spacing: 0) {
                header
                preview
                if let h = histogram {
                    HistogramView(r: h.r, g: h.g, b: h.b)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                controls
            }
        }
        .onAppear {
            runAutoDevelop()   // reveal the real sky immediately
            renderPreview()
        }
        .onChange(of: adj) { _, _ in renderPreview() }
    }

    private let llm = OnDeviceLLM.shared

    /// The signature move: analyze the frame + capture settings and auto-recover
    /// the night sky, with a plain-language explanation of what it was. The
    /// deterministic engine decides the numbers; if Apple Intelligence is
    /// available on this device, it enriches the *explanation* only.
    private func runAutoDevelop() {
        let result = AutoDevelop.develop(original, meta: meta)
        adj = result.adjustments
        autoExplanation = result.explanation

        // Optionally let the on-device model (Apple Intelligence) narrate.
        guard OnDeviceLLM.isAvailable else { return }
        let findings = result.explanation
        Task {
            if let narration = await llm.explainPhoto(autoFindings: findings) {
                await MainActor.run { autoExplanation = narration }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Discard", role: .destructive) { onDone() }
            Spacer()
            compareButton
            Spacer()
            Button {
                Task { await save() }
            } label: {
                if saving { ProgressView().tint(.white) }
                else { Text("Save").fontWeight(.semibold) }
            }
            .disabled(saving)
        }
        .padding()
        .foregroundStyle(.white)
    }

    private var preview: some View {
        ZStack {
            // Show the untouched original while pressing "compare".
            let shown = showingOriginal ? (originalPreview ?? previewImage) : previewImage
            if let img = shown {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { v, s, _ in s = v }
                            .onEnded { v in zoom = min(6, max(1, zoom * v)) }
                    )
                    .onTapGesture(count: 2) {           // double-tap resets zoom
                        withAnimation { zoom = 1 }
                    }
            } else {
                ProgressView().tint(.white)
            }

            // Top-right badges.
            VStack {
                HStack {
                    if showingOriginal {
                        Text("BEFORE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if zoom > 1.01 {
                        Text(String(format: "%.0f×", zoom * pinch))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
            }
            .padding(10)

            if let ok = savedOK {
                Label(ok ? "Saved to Photos" : "Save failed",
                      systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .padding(10)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(ok ? .green : .red)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
    }

    /// A press-and-hold "compare" button for before/after.
    private var compareButton: some View {
        Image(systemName: "rectangle.2.swap")
            .font(.system(size: 18))
            .foregroundStyle(showingOriginal ? .cyan : .white.opacity(0.7))
            .frame(width: 44, height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !showingOriginal { showingOriginal = true } }
                    .onEnded { _ in showingOriginal = false }
            )
            .accessibilityLabel("Hold to compare with the original")
    }

    private var controls: some View {
        VStack(spacing: 14) {
            // Auto-develop explanation — tells you what the shot actually was.
            if let note = autoExplanation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.yellow)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button {
                        runAutoDevelop()
                    } label: {
                        Text("Auto").font(.system(size: 12, weight: .semibold))
                    }
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            // Enhance + Crop row.
            HStack(spacing: 8) {
                Button {
                    withAnimation { adj.starBoost = adj.starBoost > 0 ? 0 : 0.7 }
                } label: {
                    Label(adj.starBoost > 0 ? "Enhance on" : "Enhance",
                          systemImage: "sparkles")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(adj.starBoost > 0 ? Color.white : Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(adj.starBoost > 0 ? .black : .white)
                }
                Button {
                    withAnimation { showCrop.toggle() }
                } label: {
                    Label("Crop", systemImage: "crop.rotate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(showCrop || !adj.geometry.isIdentity ? Color.cyan.opacity(0.85) : Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(showCrop || !adj.geometry.isIdentity ? .black : .white)
                }
            }

            if showCrop { cropPanel }

            // Tool picker.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tool.allCases, id: \.self) { t in
                        Button {
                            activeTool = t
                        } label: {
                            Text(t.rawValue)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(activeTool == t ? Color.white.opacity(0.2) : Color.white.opacity(0.06),
                                            in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            activeSlider

            Button("Reset") { withAnimation { adj = .neutral } }
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .disabled(adj.isNeutral)
        }
        .padding()
        .background(.black)
    }

    // MARK: - Crop / rotate / straighten

    private var cropPanel: some View {
        VStack(spacing: 10) {
            // Rotate 90° + aspect presets.
            HStack(spacing: 10) {
                Button {
                    withAnimation { adj.geometry.quarterTurns = (adj.geometry.quarterTurns + 1) % 4 }
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 34)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Rotate 90 degrees")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(aspectPresets, id: \.0) { name, ratio in
                            Button { setAspect(ratio) } label: {
                                Text(name)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }

            // Straighten slider.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Straighten").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%+.1f°", adj.geometry.straightenDegrees))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                }
                Slider(value: $adj.geometry.straightenDegrees, in: -15...15).tint(.cyan)
            }

            Button("Reset crop") {
                withAnimation { adj.geometry = Geometry() }
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            .disabled(adj.geometry.isIdentity)
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private let aspectPresets: [(String, CGFloat?)] = [
        ("Free", nil), ("1:1", 1), ("4:3", 4.0/3.0), ("3:2", 3.0/2.0), ("16:9", 16.0/9.0),
    ]

    /// Center-crop the frame to a target aspect ratio (nil = full frame).
    private func setAspect(_ ratio: CGFloat?) {
        guard let ratio, let img = originalPreview else {
            adj.geometry.cropNormalized = CGRect(x: 0, y: 0, width: 1, height: 1); return
        }
        let w = img.size.width, h = img.size.height
        let imgRatio = w / h
        var cw: CGFloat = 1, ch: CGFloat = 1
        if imgRatio > ratio {          // image wider than target → crop width
            cw = ratio / imgRatio
        } else {                        // taller → crop height
            ch = imgRatio / ratio
        }
        withAnimation {
            adj.geometry.cropNormalized = CGRect(
                x: (1 - cw) / 2, y: (1 - ch) / 2, width: cw, height: ch)
        }
    }

    @ViewBuilder
    private var activeSlider: some View {
        switch activeTool {
        case .enhance:    slider($adj.starBoost, 0, 1, "Faint-star boost")
        case .exposure:   slider($adj.exposure, -2, 2, "Exposure (EV)")
        case .contrast:   slider($adj.contrast, 0.5, 1.5, "Contrast")
        case .dehaze:     slider($adj.dehaze, 0, 1, "Remove light pollution / glow")
        case .highlights: slider($adj.highlights, 0.3, 1, "Highlights")
        case .shadows:    slider($adj.shadows, 0, 1, "Lift shadows")
        case .warmth:     slider($adj.warmth, -1, 1, "Warmth")
        case .saturation: slider($adj.saturation, 0, 2, "Color")
        case .vibrance:   slider($adj.vibrance, -1, 1, "Vibrance")
        }
    }

    private func slider(_ value: Binding<Double>, _ lo: Double, _ hi: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Slider(value: value, in: lo...hi).tint(.white)
        }
    }

    // MARK: - Rendering

    /// Downsample for a snappy live preview.
    private func renderPreview() {
        let target = original.extent
        guard !target.isEmpty, !target.isInfinite, !target.isNull else { return }
        let scale = min(1, 1200 / max(target.width, target.height))
        let scaled = original.transformed(by: .init(scaleX: scale, y: scale))

        // Cache the untouched original once, for the before/after compare.
        if originalPreview == nil,
           let cg = ctx.createCGImage(scaled, from: scaled.extent) {
            originalPreview = UIImage(cgImage: cg)
        }

        let out = ImageProcessor.apply(adj, to: scaled)
        // Some filters return an infinite extent — always crop back to the image.
        let bounds = out.extent.isInfinite ? scaled.extent : out.extent
        let cropped = out.cropped(to: bounds)
        if let cg = ctx.createCGImage(cropped, from: bounds) {
            previewImage = UIImage(cgImage: cg)
        }
        // Update the histogram from the processed frame (pros judge by this).
        histogram = HistogramComputer.compute(cropped)
    }

    /// Render the pipeline at full resolution and save.
    private func save() async {
        saving = true
        let out = ImageProcessor.apply(adj, to: original)
        let bounds = out.extent.isInfinite ? original.extent : out.extent
        guard !bounds.isEmpty, !bounds.isNull,
              let cg = ctx.createCGImage(out, from: bounds) else {
            saving = false; savedOK = false; return
        }
        let image = UIImage(cgImage: cg)
        let ok = await PhotoLibrary.save(image)
        await MainActor.run {
            saving = false
            withAnimation { savedOK = ok }
        }
    }
}

/// Small Photos helper shared by capture + editor.
enum PhotoLibrary {
    static func save(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { ok, _ in cont.resume(returning: ok) })
        }
    }
}
