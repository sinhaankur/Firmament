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

    private let ctx = CIContext()

    enum Tool: String, CaseIterable {
        case enhance = "Enhance", exposure = "Exposure", contrast = "Contrast"
        case warmth = "Warmth", saturation = "Color", shadows = "Shadows"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
            controls
        }
        .background(.black)
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
            Text("Edit").font(.headline).foregroundStyle(.white)
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
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
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

            // One-tap astro enhance.
            Button {
                withAnimation { adj.starBoost = adj.starBoost > 0 ? 0 : 0.7 }
            } label: {
                Label(adj.starBoost > 0 ? "Enhance on" : "Enhance (reveal faint stars)",
                      systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(adj.starBoost > 0 ? Color.white : Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(adj.starBoost > 0 ? .black : .white)
            }

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

    @ViewBuilder
    private var activeSlider: some View {
        switch activeTool {
        case .enhance:    slider($adj.starBoost, -0, 1, "Faint-star boost")
        case .exposure:   slider($adj.exposure, -2, 2, "Exposure (EV)")
        case .contrast:   slider($adj.contrast, 0.5, 1.5, "Contrast")
        case .warmth:     slider($adj.warmth, -1, 1, "Warmth")
        case .saturation: slider($adj.saturation, 0, 2, "Color")
        case .shadows:    slider($adj.shadows, 0, 1, "Lift shadows")
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
        let scale = min(1, 1200 / max(target.width, target.height))
        let scaled = original.transformed(by: .init(scaleX: scale, y: scale))
        let out = ImageProcessor.apply(adj, to: scaled)
        if let cg = ctx.createCGImage(out, from: out.extent) {
            previewImage = UIImage(cgImage: cg)
        }
    }

    /// Render the pipeline at full resolution and save.
    private func save() async {
        saving = true
        let out = ImageProcessor.apply(adj, to: original)
        guard let cg = ctx.createCGImage(out, from: out.extent) else {
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
