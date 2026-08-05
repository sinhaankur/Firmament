import Foundation

/// Tracks the ISS for the observer: current alt/az from SGP4, and a scan for the
/// next visible pass. Uses a bundled TLE (refreshable). The TLE ages, so the
/// position drifts over weeks — the UI labels it as "based on a stored orbit" to
/// stay honest; a live TLE fetch is a drop-in upgrade.
///
/// © Ankur Sinha.
struct ISSTracker {

    /// A bundled recent ISS (ZARYA) TLE. Replaceable; the epoch is parsed from
    /// the lines so an updated pair Just Works.
    static let issName = "ISS (ZARYA)"
    static let issLine1 = "1 25544U 98067A   26210.54791667  .00016717  00000-0  10270-3 0  9004"
    static let issLine2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.50377579 20000"

    let sgp4: SGP4?

    init(line1: String = ISSTracker.issLine1, line2: String = ISSTracker.issLine2) {
        sgp4 = SGP4(line1: line1, line2: line2)
    }

    /// Current look angle (alt/az, degrees) + range (km) + sub-point, for the
    /// observer at `lat`/`lon` (deg) and `date`.
    func lookAngle(latitude: Double, longitude: Double, at date: Date)
        -> (altitude: Double, azimuth: Double, rangeKm: Double)?
    {
        guard let sgp4 else { return nil }
        let jd = SkyMath.julianDay(from: date)
        let tsince = (jd - sgp4.epochJD) * 1440.0     // minutes since epoch
        let sv = sgp4.propagate(minutesSinceEpoch: tsince)

        // TEME → ECEF: rotate by the Greenwich sidereal angle.
        let gmstRad = SkyMath.deg2rad(SkyMath.gmstDegrees(jd))
        let cosG = cos(gmstRad), sinG = sin(gmstRad)
        let xEcef = sv.x * cosG + sv.y * sinG
        let yEcef = -sv.x * sinG + sv.y * cosG
        let zEcef = sv.z

        // Observer ECEF position (spherical Earth is fine for pointing).
        let lat = SkyMath.deg2rad(latitude)
        let lon = SkyMath.deg2rad(longitude)
        let re = 6378.135
        let obsX = re * cos(lat) * cos(lon)
        let obsY = re * cos(lat) * sin(lon)
        let obsZ = re * sin(lat)

        // Range vector, rotated into the topocentric (SEZ) frame.
        let rx = xEcef - obsX
        let ry = yEcef - obsY
        let rz = zEcef - obsZ
        let sinLat = sin(lat), cosLat = cos(lat)
        let sinLon = sin(lon), cosLon = cos(lon)
        let south = sinLat * cosLon * rx + sinLat * sinLon * ry - cosLat * rz
        let east = -sinLon * rx + cosLon * ry
        let up = cosLat * cosLon * rx + cosLat * sinLon * ry + sinLat * rz

        let range = sqrt(rx * rx + ry * ry + rz * rz)
        let alt = SkyMath.rad2deg(asin(up / range))
        var az = SkyMath.rad2deg(atan2(east, -south))
        if az < 0 { az += 360 }
        return (alt, az, range)
    }

    /// Scan forward for the next pass that rises above `minAltitude` degrees.
    /// Returns the start time and peak altitude, or nil if none in the window.
    func nextPass(latitude: Double, longitude: Double, from date: Date,
                  minAltitude: Double = 10, withinHours: Double = 24)
        -> (start: Date, peakAltitude: Double, peakAzimuth: Double)?
    {
        let step = 30.0 // seconds
        var t = date
        let end = date.addingTimeInterval(withinHours * 3600)
        var inPass = false
        var passStart: Date?
        var peak = -90.0
        var peakAz = 0.0

        while t < end {
            guard let look = lookAngle(latitude: latitude, longitude: longitude, at: t) else { return nil }
            if look.altitude >= minAltitude {
                if !inPass { inPass = true; passStart = t; peak = look.altitude; peakAz = look.azimuth }
                else if look.altitude > peak { peak = look.altitude; peakAz = look.azimuth }
            } else if inPass {
                // Pass ended — return the one we just tracked.
                if let start = passStart { return (start, peak, peakAz) }
            }
            t = t.addingTimeInterval(step)
        }
        if inPass, let start = passStart { return (start, peak, peakAz) }
        return nil
    }
}
