import XCTest
@testable import NightSky

/// Tests for the capture presets, the star catalog loader, and the image
/// adjustment defaults — the non-astronomy pieces that still need to be right.
final class CaptureAndCatalogTests: XCTestCase {

    /// Every bundled preset has sane, non-degenerate values.
    func testPresetsAreValid() {
        XCTAssertFalse(CapturePreset.all.isEmpty)
        var seen = Set<String>()
        for p in CapturePreset.all {
            XCTAssertFalse(p.name.isEmpty)
            XCTAssertTrue(seen.insert(p.id).inserted, "duplicate preset id \(p.id)")
            XCTAssertGreaterThan(p.iso, 0)
            XCTAssertGreaterThan(p.shutterSeconds, 0)
            XCTAssertGreaterThanOrEqual(p.totalExposureSeconds, 0)
            XCTAssertGreaterThanOrEqual(p.zoom, 1)
            XCTAssertFalse(p.hint.isEmpty)
        }
    }

    /// The star catalog loads a real, sizeable set with the brightest first and
    /// proper names present (Sirius should be there and bright).
    func testStarCatalogLoads() {
        let all = StarCatalog.all
        XCTAssertGreaterThan(all.count, 1000, "expected the full HYG naked-eye set")
        // Sorted brightest-first: the first star is very bright.
        XCTAssertLessThan(all.first!.magnitude, 0)
        // A well-known named star resolves.
        XCTAssertNotNil(StarCatalog.star(named: "Sirius"))
        XCTAssertNotNil(StarCatalog.star(named: "Vega"))
        // All magnitudes are within the naked-eye cutoff.
        XCTAssertTrue(all.allSatisfy { $0.magnitude <= 6.6 })
    }

    /// Constellation figures only reference stars that exist by name.
    func testConstellationStarsExist() {
        for figure in Constellations.all {
            for name in figure.path {
                XCTAssertNotNil(StarCatalog.star(named: name),
                                "constellation \(figure.name) references missing star \(name)")
            }
        }
    }

    /// Neutral adjustments are a no-op flag; changing any field breaks neutrality.
    func testImageAdjustmentsNeutral() {
        XCTAssertTrue(ImageAdjustments.neutral.isNeutral)
        var a = ImageAdjustments.neutral
        a.exposure = 1.0
        XCTAssertFalse(a.isNeutral)
    }

    /// AutoDevelop on a synthetic dark frame recommends lifting exposure.
    func testAutoDevelopLiftsDarkFrame() {
        // A 4×4 nearly-black image.
        let dark = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.03))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let result = AutoDevelop.develop(dark, meta: .init(iso: 3200, exposureSeconds: 1))
        XCTAssertGreaterThan(result.adjustments.exposure, 0, "dark frame should be lifted")
        XCTAssertFalse(result.explanation.isEmpty)
        XCTAssertLessThan(result.meanLuma, 0.12)
    }
}
