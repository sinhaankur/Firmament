//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import SwiftUI

/// The multi-track timeline strip at the bottom of the video editor.
///
/// It renders each track as a horizontal lane of clips against a shared time
/// axis, with a draggable playhead. It's presentation-only: it reads a
/// `Timeline` and a bound `playhead` (seconds) and reports scrubs back through
/// `onScrub`. The editor owns playback and the model; this view owns none of it.
///
/// Layout is time-proportional: 1 second = `pointsPerSecond` points, so the
/// whole strip scrolls horizontally and can later be pinch-zoomed by changing
/// that scale. The filmstrip thumbnails for the video track are passed in so
/// this view stays free of AVFoundation.
///
/// Named `EditorTimeline` (not `TimelineView`) to avoid confusion with SwiftUI's
/// own `TimelineView`.
struct EditorTimeline: View {
    let timeline: Timeline
    /// Current playhead position in seconds (drives the vertical line).
    @Binding var playhead: Double
    /// Evenly-spaced filmstrip thumbnails for the video track, left→right.
    var thumbnails: [UIImage] = []
    /// Called as the user scrubs (drags the playhead or taps a time).
    var onScrub: (Double) -> Void = { _ in }
    /// Called when a clip/item is tapped (id), for selection.
    var onSelectItem: (UUID) -> Void = { _ in }
    /// Currently-selected item id, highlighted.
    var selectedItemID: UUID?

    /// Horizontal scale. 44 pt/s keeps a ~20 s clip comfortably scrollable.
    private let pointsPerSecond: CGFloat = 44
    private let laneHeight: CGFloat = 44
    private let laneSpacing: CGFloat = 6
    private let labelColumnWidth: CGFloat = 34

    private var contentWidth: CGFloat {
        max(1, CGFloat(timeline.duration) * pointsPerSecond)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            trackLabels
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Scrub layer is at the BACK so clip taps (onSelectItem) land
                    // on the clips above it. It only claims real drags
                    // (minimumDistance), so a tap on empty timeline still scrubs
                    // via the trailing tap gesture, and a tap on a clip selects.
                    scrubSurface
                    lanes.allowsHitTesting(true)
                    playheadLine
                }
                .frame(width: contentWidth, alignment: .topLeading)
            }
        }
    }

    // MARK: - Track name column (fixed, doesn't scroll)

    private var trackLabels: some View {
        VStack(spacing: laneSpacing) {
            timeRulerSpacer
            ForEach(timeline.tracks) { track in
                Text(track.kind.displayName)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: labelColumnWidth, height: laneHeight, alignment: .leading)
            }
        }
    }

    /// Blank cell aligning the label column with the ruler row.
    private var timeRulerSpacer: some View {
        Color.clear.frame(width: labelColumnWidth, height: rulerHeight)
    }

    private let rulerHeight: CGFloat = 14

    // MARK: - Lanes

    private var lanes: some View {
        VStack(alignment: .leading, spacing: laneSpacing) {
            timeRuler
            ForEach(timeline.tracks) { track in
                lane(for: track)
            }
        }
    }

    /// Second ticks + labels along the top so the time axis is legible.
    private var timeRuler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rulerTicks, id: \.self) { second in
                let x = CGFloat(second) * pointsPerSecond
                VStack(spacing: 1) {
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 4)
                    Text(timeLabel(second))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .offset(x: x)
            }
        }
        .frame(height: rulerHeight, alignment: .topLeading)
    }

    /// Whole-second ticks, but thinned out so labels never crowd on long clips.
    private var rulerTicks: [Int] {
        let total = Int(timeline.duration.rounded(.up))
        guard total > 0 else { return [0] }
        // Aim for ≤ ~12 labels: step up in nice increments.
        let step = max(1, Int((Double(total) / 12).rounded(.up)))
        return stride(from: 0, through: total, by: step).map { $0 }
    }

    private func timeLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private func lane(for track: TimelineTrack) -> some View {
        ZStack(alignment: .leading) {
            // Lane background — non-interactive so taps on empty timeline fall
            // through to the scrub layer behind it.
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04))
                .frame(height: laneHeight)
                .allowsHitTesting(false)

            // The video lane shows a filmstrip behind its clip(s); other lanes
            // show colored item blocks.
            if track.kind == .video {
                filmstrip.frame(height: laneHeight).clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
            }

            ForEach(track.items) { item in
                clipBlock(item, kind: track.kind)
            }
        }
        .frame(width: contentWidth, height: laneHeight, alignment: .leading)
    }

    /// A single clip/item block, positioned + sized by its time range.
    private func clipBlock(_ item: TimelineItem, kind: TrackKind) -> some View {
        let x = CGFloat(item.start) * pointsPerSecond
        let w = max(10, CGFloat(item.duration) * pointsPerSecond)
        let selected = item.id == selectedItemID
        return RoundedRectangle(cornerRadius: 6)
            .fill(color(for: kind).opacity(kind == .video ? 0.0 : 0.7))
            .overlay(alignment: .leading) {
                if kind != .video {
                    Text(item.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.white : color(for: kind).opacity(0.9),
                            lineWidth: selected ? 2 : 1)
            )
            .frame(width: w, height: laneHeight - 4)
            .offset(x: x)
            .onTapGesture { onSelectItem(item.id) }
    }

    private func color(for kind: TrackKind) -> Color {
        switch kind {
        case .video:  return Theme.accent
        case .effect: return Theme.warning
        case .text:   return Theme.good
        case .audio:  return .white.opacity(0.5)
        }
    }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle().fill(.white.opacity(0.06))
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: contentWidth / CGFloat(thumbnails.count), height: laneHeight)
                        .clipped()
                }
            }
        }
    }

    // MARK: - Playhead + scrubbing

    private var playheadX: CGFloat { CGFloat(timeline.clampTime(playhead)) * pointsPerSecond }

    private var lanesHeight: CGFloat {
        rulerHeight + CGFloat(timeline.tracks.count) * (laneHeight + laneSpacing)
    }

    private var playheadLine: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.white).frame(width: 2, height: lanesHeight)
            Circle().fill(Color.white).frame(width: 10, height: 10).offset(y: -3)
        }
        .offset(x: playheadX - 1)
        .allowsHitTesting(false)
    }

    /// A transparent full-area surface behind the lanes that turns taps and
    /// drags on empty timeline into scrubs. It sits at the back of the ZStack, so
    /// clip blocks above it still receive their selection taps; only gestures
    /// that don't hit a clip reach here.
    private var scrubSurface: some View {
        Color.clear
            .frame(width: contentWidth, height: lanesHeight)
            .contentShape(Rectangle())
            // Tap anywhere on empty timeline → scrub to that point.
            .onTapGesture { location in
                onScrub(timeline.clampTime(Double(max(0, location.x) / pointsPerSecond)))
            }
            // Drag → continuous scrub.
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        onScrub(timeline.clampTime(Double(max(0, g.location.x) / pointsPerSecond)))
                    }
            )
    }
}
