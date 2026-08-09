//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation
import CoreGraphics

/// The editor's timeline model — the data behind the multi-track editor.
///
/// This is a pure value type: it knows nothing about SwiftUI, AVFoundation, or
/// rendering. The `VideoEditorView` builds a `Timeline` from the imported clip
/// and mutates it as the user edits; the composition/export path reads it back.
///
/// Time is measured in **seconds** from the start of the timeline. Keeping the
/// model UI- and framework-free is what makes it unit-testable (see
/// `TimelineTests`) and what will let auto-cut / AI-suggestion features operate
/// on edits as plain data, not view state.

/// Which lane an item lives on. Order here is top-to-bottom render order in the
/// editor (video at the base, overlays above it).
enum TrackKind: String, CaseIterable, Identifiable {
    case video      // the source clip(s)
    case effect     // a graded look applied over a span (e.g. Night Recover)
    case text       // a caption burned in over a span
    case audio      // the clip's audio waveform (display-only for now)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video:  return "Video"
        case .effect: return "FX"
        case .text:   return "Text"
        case .audio:  return "Audio"
        }
    }

    /// Row order in the editor (video first / topmost row, audio last).
    static var editorOrder: [TrackKind] { [.video, .effect, .text, .audio] }
}

/// A single object placed on a track over a span of the timeline.
struct TimelineItem: Identifiable, Equatable {
    let id: UUID
    /// Where it begins on the timeline (seconds).
    var start: Double
    /// How long it lasts (seconds).
    var duration: Double
    /// A short label shown on the clip (filename, "Night Recover", caption text…).
    var label: String

    init(id: UUID = UUID(), start: Double, duration: Double, label: String) {
        self.id = id
        self.start = start
        self.duration = max(0, duration)
        self.label = label
    }

    /// The half-open time range [start, end) this item occupies.
    var end: Double { start + duration }

    /// Whether a given timeline time falls inside this item.
    func contains(_ time: Double) -> Bool { time >= start && time < end }
}

/// One horizontal lane of the timeline, holding items of a single kind.
struct TimelineTrack: Identifiable, Equatable {
    let id: UUID
    let kind: TrackKind
    var items: [TimelineItem]

    init(id: UUID = UUID(), kind: TrackKind, items: [TimelineItem] = []) {
        self.id = id
        self.kind = kind
        self.items = items
    }

    var isEmpty: Bool { items.isEmpty }
}

/// The whole timeline: a fixed set of tracks plus the total content duration.
struct Timeline: Equatable {
    var tracks: [TimelineTrack]
    /// Total timeline length in seconds (usually the source clip's duration).
    var duration: Double

    /// An empty timeline with one lane per kind, sized to `duration`.
    static func empty(duration: Double) -> Timeline {
        Timeline(
            tracks: TrackKind.editorOrder.map { TimelineTrack(kind: $0) },
            duration: max(0, duration)
        )
    }

    /// Build the initial timeline for a freshly imported single clip: the whole
    /// clip on the video track, everything else empty. `label` is a short name
    /// for the clip (e.g. the file name).
    static func singleClip(duration: Double, label: String = "Clip") -> Timeline {
        var t = empty(duration: duration)
        t.setItems([TimelineItem(start: 0, duration: max(0, duration), label: label)],
                   on: .video)
        return t
    }

    // MARK: - Track access

    /// The track for a kind, if present.
    func track(_ kind: TrackKind) -> TimelineTrack? {
        tracks.first { $0.kind == kind }
    }

    /// Replace all items on a kind's track (creating the track if missing).
    mutating func setItems(_ items: [TimelineItem], on kind: TrackKind) {
        if let idx = tracks.firstIndex(where: { $0.kind == kind }) {
            tracks[idx].items = items
        } else {
            tracks.append(TimelineTrack(kind: kind, items: items))
        }
    }

    /// Add one item to a kind's track (creating the track if missing).
    mutating func add(_ item: TimelineItem, to kind: TrackKind) {
        if let idx = tracks.firstIndex(where: { $0.kind == kind }) {
            tracks[idx].items.append(item)
        } else {
            tracks.append(TimelineTrack(kind: kind, items: [item]))
        }
    }

    /// Remove an item by id from whichever track holds it.
    mutating func remove(itemID: UUID) {
        for i in tracks.indices {
            tracks[i].items.removeAll { $0.id == itemID }
        }
    }

    /// All items on a kind's track (empty if the track is absent).
    func items(on kind: TrackKind) -> [TimelineItem] {
        track(kind)?.items ?? []
    }

    // MARK: - Time helpers

    /// Clamp a time to the valid [0, duration] window.
    func clampTime(_ t: Double) -> Double { min(duration, max(0, t)) }

    /// Map a timeline time to a normalized 0…1 position (for layout).
    func normalized(_ t: Double) -> Double {
        guard duration > 0 else { return 0 }
        return clampTime(t) / duration
    }
}
