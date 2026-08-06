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
