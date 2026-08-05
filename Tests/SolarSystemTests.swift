import XCTest
@testable import NightSky

/// Tests for the Sun/Moon/planet ephemeris. These check the bodies land in
/// astronomically sane ranges — the guardrail against a sign flip or unit error
/// silently putting Mars on the wrong side of the sky.
final class SolarSystemTests: XCTestCase {

    private let jd = SkyMath.julianDay(from: Date())

    /// The Sun's declination stays within the obliquity band (±23.5°).
    func testSunDeclinationInBand() {
        let sun = SolarSystem.sun(jd: jd)
        XCTAssertLessThanOrEqual(abs(sun.decDeg), 23.6)
        XCTAssertGreaterThanOrEqual(sun.raDeg, 0)
        XCTAssertLessThan(sun.raDeg, 360)
        // Earth-Sun distance is ~1 AU.
        XCTAssertEqual(sun.distanceAU, 1.0, accuracy: 0.03)
    }

    /// The Moon sits within ~5.2° of the ecliptic, so its declination band is
    /// wider than the Sun's but still bounded (~±28.6°).
    func testMoonDeclinationBand() {
        let moon = SolarSystem.moon(jd: jd)
        XCTAssertLessThanOrEqual(abs(moon.decDeg), 29)
        // Earth-Moon distance is ~356,500–406,700 km.
        XCTAssertGreaterThan(moon.distanceKm, 350_000)
        XCTAssertLessThan(moon.distanceKm, 410_000)
    }

    /// Moon illumination is a fraction in [0, 1].
    func testMoonPhaseFraction() {
        let phase = SolarSystem.moonPhase(jd: jd)
        XCTAssertGreaterThanOrEqual(phase.illumination, 0)
        XCTAssertLessThanOrEqual(phase.illumination, 1)
    }

    /// Every visible planet resolves and sits in a sane geocentric distance.
    func testPlanetsResolveInRange() {
        // Rough max Earth distances (AU) as an upper bound sanity check.
        let maxAU: [Planet: Double] = [
            .mercury: 1.6, .venus: 1.8, .mars: 2.7, .jupiter: 6.6,
            .saturn: 11.1, .uranus: 21.2, .neptune: 31.4,
        ]
        for p in Planet.visible {
            guard let pos = SolarSystem.planet(p, jd: jd) else {
                XCTFail("Planet \(p) did not resolve"); continue
            }
            XCTAssertGreaterThanOrEqual(pos.raDeg, 0)
            XCTAssertLessThan(pos.raDeg, 360)
            XCTAssertLessThanOrEqual(abs(pos.decDeg), 90)
            XCTAssertGreaterThan(pos.distanceAU, 0)
            XCTAssertLessThan(pos.distanceAU, (maxAU[p] ?? 40) + 1)
        }
    }

    /// The NightSkyEngine composes everything without crashing and returns a
    /// non-empty sky (Sun + Moon + planets + stars).
    func testEngineComposesFullSky() {
        let engine = NightSkyEngine(observer: .init(latitude: 40, longitude: -74))
        let objects = engine.allObjects(at: Date())
        XCTAssertGreaterThan(objects.count, 50)   // stars dominate the count
        XCTAssertTrue(objects.contains { $0.id == "sun" })
        XCTAssertTrue(objects.contains { $0.id == "moon" })
    }
}
