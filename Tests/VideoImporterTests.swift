//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import XCTest
import CoreImage
@testable import NightSky

/// Proves the video → stacked-still pipeline actually produces a frame (not just
/// compiles). This is the exact path a picked library video takes; the bug it
/// guards against is the importer hanging or returning nil.
final class VideoImporterTests: XCTestCase {

    func testStacksRealVideoIntoFrame() async throws {
        // The bundled 2s test clip.
        guard let url = Bundle(for: Self.self).url(forResource: "testvid", withExtension: "mov") else {
            throw XCTSkip("test video not bundled")
        }
        let out = await VideoImporter().stackedFrame(from: url)
        XCTAssertNotNil(out, "stacking a real video must produce a frame")
        if let out {
            XCTAssertFalse(out.extent.isEmpty)
            XCTAssertFalse(out.extent.isInfinite)
            XCTAssertGreaterThan(out.extent.width, 0)
            XCTAssertGreaterThan(out.extent.height, 0)
        }
    }

    /// Every video filter maps to a distinct, non-degenerate adjustment; only
    /// "None" is neutral.
    func testVideoFiltersAreDistinct() {
        for f in VideoFilter.allCases {
            let base = f.base
            if f == .none {
                XCTAssertTrue(base.isNeutral)
            } else {
                XCTAssertFalse(base.isNeutral, "\(f.rawValue) should change the image")
            }
        }
        // Night Recover is the signature: lifts exposure + removes glow.
        XCTAssertGreaterThan(VideoFilter.nightRecover.base.exposure, 0)
        XCTAssertGreaterThan(VideoFilter.nightRecover.base.dehaze, 0)
        // Mono desaturates.
        XCTAssertEqual(VideoFilter.mono.base.saturation, 0)
    }

    /// A text overlay renders to a frame-sized CIImage; empty text renders nil.
    func testTextOverlayRenders() {
        let extent = CGRect(x: 0, y: 0, width: 640, height: 360)
        var o = TextOverlay()
        XCTAssertNil(VideoAdjust.renderText(o, in: extent), "empty caption → nil")
        o.text = "Milky Way over the ridge"
        let img = VideoAdjust.renderText(o, in: extent)
        XCTAssertNotNil(img)
        if let img {
            XCTAssertEqual(img.extent.width, 640, accuracy: 1)
            XCTAssertEqual(img.extent.height, 360, accuracy: 1)
        }
        // A caption makes the adjustment non-neutral (so it triggers export).
        var adj = VideoAdjust(); adj.overlay = o
        XCTAssertFalse(adj.isNeutral)
    }

    /// A bogus URL returns nil quickly (within the timeout) — never hangs.
    func testBadVideoReturnsNilFast() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist.mov")
        let start = Date()
        let out = await VideoImporter().stackedFrame(from: bogus)
        XCTAssertNil(out)
        XCTAssertLessThan(Date().timeIntervalSince(start), 13, "must fail fast, not hang")
    }
}
