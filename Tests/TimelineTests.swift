//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import XCTest
@testable import NightSky

/// Tests for the editor's timeline model — the pure value type behind the
/// multi-track video editor. Locks in construction, item placement, and the
/// time helpers the timeline view lays out against.
final class TimelineTests: XCTestCase {

    func testEmptyHasOneLanePerKind() {
        let t = Timeline.empty(duration: 10)
        XCTAssertEqual(t.tracks.count, TrackKind.editorOrder.count)
        for kind in TrackKind.editorOrder {
            XCTAssertNotNil(t.track(kind), "missing lane for \(kind)")
            XCTAssertTrue(t.items(on: kind).isEmpty)
        }
        XCTAssertEqual(t.duration, 10, accuracy: 1e-9)
    }

    func testSingleClipPutsWholeClipOnVideoTrack() {
        let t = Timeline.singleClip(duration: 20, label: "Meteor")
        let video = t.items(on: .video)
        XCTAssertEqual(video.count, 1)
        let clip = try? XCTUnwrap(video.first)
        XCTAssertEqual(clip?.start, 0)
        XCTAssertEqual(clip?.duration ?? -1, 20, accuracy: 1e-9)
        XCTAssertEqual(clip?.label, "Meteor")
        // Other lanes stay empty.
        XCTAssertTrue(t.items(on: .effect).isEmpty)
        XCTAssertTrue(t.items(on: .text).isEmpty)
    }

    func testItemContainsAndEnd() {
        let item = TimelineItem(start: 5, duration: 3, label: "x")
        XCTAssertEqual(item.end, 8, accuracy: 1e-9)
        XCTAssertTrue(item.contains(5))
        XCTAssertTrue(item.contains(7.999))
        XCTAssertFalse(item.contains(8))      // half-open range
        XCTAssertFalse(item.contains(4.999))
    }

    func testNegativeDurationClampsToZero() {
        let item = TimelineItem(start: 2, duration: -4, label: "x")
        XCTAssertEqual(item.duration, 0)
        XCTAssertEqual(item.end, 2)
    }

    func testAddAndRemoveItem() {
        var t = Timeline.empty(duration: 30)
        let a = TimelineItem(start: 1, duration: 2, label: "a")
        let b = TimelineItem(start: 4, duration: 2, label: "b")
        t.add(a, to: .text)
        t.add(b, to: .text)
        XCTAssertEqual(t.items(on: .text).count, 2)
        t.remove(itemID: a.id)
        XCTAssertEqual(t.items(on: .text).map(\.label), ["b"])
    }

    func testSetItemsReplacesLane() {
        var t = Timeline.singleClip(duration: 12)
        t.setItems([TimelineItem(start: 0, duration: 12, label: "Night Recover")], on: .effect)
        XCTAssertEqual(t.items(on: .effect).map(\.label), ["Night Recover"])
        t.setItems([], on: .effect)
        XCTAssertTrue(t.items(on: .effect).isEmpty)
    }

    func testClampAndNormalize() {
        let t = Timeline.empty(duration: 10)
        XCTAssertEqual(t.clampTime(-5), 0)
        XCTAssertEqual(t.clampTime(15), 10)
        XCTAssertEqual(t.clampTime(4), 4)
        XCTAssertEqual(t.normalized(0), 0, accuracy: 1e-9)
        XCTAssertEqual(t.normalized(5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.normalized(10), 1, accuracy: 1e-9)
        XCTAssertEqual(t.normalized(20), 1, accuracy: 1e-9)   // clamped
    }

    func testNormalizeZeroDurationIsSafe() {
        let t = Timeline.empty(duration: 0)
        XCTAssertEqual(t.normalized(5), 0)   // no divide-by-zero
    }
}
