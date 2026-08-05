import XCTest
@testable import NightSky

/// Regression tests for the from-scratch SGP4 propagator. These lock in the
/// numbers verified by hand: the ISS orbits at ~400–420 km altitude and
/// ~7.66 km/s. If a refactor breaks the orbital mechanics, these fail loudly.
final class SGP4Tests: XCTestCase {

    private let earthRadiusKm = 6378.135

    func testISSParsesAndPropagates() {
        guard let sgp4 = SGP4(
            line1: SatelliteCatalog.bright[0].line1,
            line2: SatelliteCatalog.bright[0].line2) else {
            XCTFail("ISS TLE failed to parse"); return
        }
        // Epoch should be a plausible modern Julian Day.
        XCTAssertGreaterThan(sgp4.epochJD, 2_400_000)

        for minutes in [0.0, 30.0, 60.0, 90.0] {
            let v = sgp4.propagate(minutesSinceEpoch: minutes)
            let r = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            let altitude = r - earthRadiusKm
            let speed = (v.vx * v.vx + v.vy * v.vy + v.vz * v.vz).squareRoot()

            // ISS altitude band and orbital speed — the real numbers.
            XCTAssertGreaterThan(altitude, 380, "alt too low at \(minutes) min")
            XCTAssertLessThan(altitude, 440, "alt too high at \(minutes) min")
            XCTAssertEqual(speed, 7.66, accuracy: 0.15, "speed off at \(minutes) min")

            // No NaNs.
            XCTAssertFalse(r.isNaN)
            XCTAssertFalse(speed.isNaN)
        }
    }

    /// The tracker resolves a look angle for every catalog satellite.
    func testTrackerLookAngles() {
        let tracker = SatelliteTracker()
        XCTAssertFalse(tracker.satellites.isEmpty)
        for sat in tracker.satellites {
            let fix = tracker.fix(for: sat, latitude: 40, longitude: -74, at: Date())
            XCTAssertNotNil(fix)
            if let f = fix {
                XCTAssertLessThanOrEqual(abs(f.altitude), 90.001)
                XCTAssertGreaterThanOrEqual(f.azimuth, -0.001)
                XCTAssertLessThan(f.azimuth, 360.001)
                XCTAssertGreaterThan(f.rangeKm, 0)
            }
        }
    }
}
