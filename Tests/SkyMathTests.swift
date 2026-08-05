//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import XCTest
@testable import NightSky

/// Tests for the core astronomical math. These pin the fidelity the whole app
/// rests on: get these wrong and every label lands in the wrong place.
final class SkyMathTests: XCTestCase {

    /// J2000.0 epoch (2000-01-01 12:00 TT) has the exact Julian Day 2451545.0.
    func testJulianDayAtJ2000() {
        var comps = DateComponents()
        comps.year = 2000; comps.month = 1; comps.day = 1
        comps.hour = 12; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let jd = SkyMath.julianDay(from: date)
        XCTAssertEqual(jd, 2451545.0, accuracy: 1e-4)
    }

    /// Angle normalization stays within [0, 360).
    func testNorm360() {
        XCTAssertEqual(SkyMath.norm360(370), 10, accuracy: 1e-9)
        XCTAssertEqual(SkyMath.norm360(-30), 330, accuracy: 1e-9)
        XCTAssertEqual(SkyMath.norm360(0), 0, accuracy: 1e-9)
        XCTAssertLessThan(SkyMath.norm360(720.5), 360)
    }

    /// GMST at J2000.0 is ~280.46° (Meeus). Sanity, not sub-arcsecond.
    func testGMSTAtJ2000() {
        let gmst = SkyMath.gmstDegrees(2451545.0)
        XCTAssertEqual(gmst, 280.46, accuracy: 0.1)
    }

    /// Obliquity of the ecliptic at J2000 is ~23.4393°.
    func testObliquity() {
        let eps = SkyMath.obliquityDegrees(2451545.0)
        XCTAssertEqual(eps, 23.4393, accuracy: 0.001)
    }

    /// An object at the observer's zenith direction should read ~90° altitude.
    /// Place the observer on the equator; a point with dec=0 and hour angle 0
    /// (i.e. RA == local sidereal time) is straight up.
    func testZenithAltitude() {
        let jd = 2451545.0
        let lat = 0.0, lon = 0.0
        let lst = SkyMath.lstDegrees(jd: jd, longitudeEast: lon)
        // Object with RA == LST, Dec == latitude → at the zenith.
        let h = SkyMath.equatorialToHorizontal(
            raDeg: lst, decDeg: lat, latitude: lat, longitude: lon, jd: jd)
        XCTAssertEqual(h.altitude, 90, accuracy: 0.5)
    }

    /// Alt/az round-trips stay on the sphere: altitude within [-90, 90].
    func testAltitudeBounds() {
        let jd = SkyMath.julianDay(from: Date())
        for ra in stride(from: 0.0, to: 360.0, by: 45) {
            for dec in stride(from: -80.0, through: 80.0, by: 40) {
                let h = SkyMath.equatorialToHorizontal(
                    raDeg: ra, decDeg: dec, latitude: 40, longitude: -74, jd: jd)
                XCTAssertGreaterThanOrEqual(h.altitude, -90.001)
                XCTAssertLessThanOrEqual(h.altitude, 90.001)
                XCTAssertGreaterThanOrEqual(h.azimuth, -0.001)
                XCTAssertLessThan(h.azimuth, 360.001)
            }
        }
    }

    /// Refraction lifts a horizon object slightly (positive correction near 0°).
    func testRefractionLiftsHorizon() {
        let refracted = SkyMath.refractedAltitude(0)
        XCTAssertGreaterThan(refracted, 0)          // it's lifted above 0
        XCTAssertLessThan(refracted, 1)             // but by well under a degree
    }
}
