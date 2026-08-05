import Foundation

/// Tracks several bright satellites at once and answers the questions Spot mode
/// needs: which one is up right now, which is *closest*, and when the next
/// visible pass is. Built on the from-scratch `SGP4` propagator.
///
/// © Ankur Sinha.
struct SatelliteTracker {

    struct Tracked {
        let name: String
        let sgp4: SGP4
    }

    struct Fix {
        let name: String
        let altitude: Double     // degrees above horizon
        let azimuth: Double      // 0=N, 90=E
        let rangeKm: Double
        var isUp: Bool { altitude > 0 }
    }

    struct Pass {
        let name: String
        let start: Date
        let peakAltitude: Double
        let peakAzimuth: Double
    }

    let satellites: [Tracked]

    init(catalog: [SatelliteTLE] = SatelliteCatalog.bright) {
        satellites = catalog.compactMap { tle in
            SGP4(line1: tle.line1, line2: tle.line2).map { Tracked(name: tle.name, sgp4: $0) }
        }
    }

    /// Look angle for one satellite.
    func fix(for tracked: Tracked, latitude: Double, longitude: Double, at date: Date) -> Fix? {
        let jd = SkyMath.julianDay(from: date)
        let tsince = (jd - tracked.sgp4.epochJD) * 1440.0
        let sv = tracked.sgp4.propagate(minutesSinceEpoch: tsince)

        let gmstRad = SkyMath.deg2rad(SkyMath.gmstDegrees(jd))
        let cosG = cos(gmstRad), sinG = sin(gmstRad)
        let xE = sv.x * cosG + sv.y * sinG
        let yE = -sv.x * sinG + sv.y * cosG
        let zE = sv.z

        let lat = SkyMath.deg2rad(latitude), lon = SkyMath.deg2rad(longitude)
        let re = 6378.135
        let oX = re * cos(lat) * cos(lon)
        let oY = re * cos(lat) * sin(lon)
        let oZ = re * sin(lat)

        let rx = xE - oX, ry = yE - oY, rz = zE - oZ
        let sinLat = sin(lat), cosLat = cos(lat), sinLon = sin(lon), cosLon = cos(lon)
        let south = sinLat * cosLon * rx + sinLat * sinLon * ry - cosLat * rz
        let east = -sinLon * rx + cosLon * ry
        let up = cosLat * cosLon * rx + cosLat * sinLon * ry + sinLat * rz
        let range = sqrt(rx * rx + ry * ry + rz * rz)
        let alt = SkyMath.rad2deg(asin(up / range))
        var az = SkyMath.rad2deg(atan2(east, -south))
        if az < 0 { az += 360 }
        return Fix(name: tracked.name, altitude: alt, azimuth: az, rangeKm: range)
    }

    /// All satellites' current fixes.
    func allFixes(latitude: Double, longitude: Double, at date: Date) -> [Fix] {
        satellites.compactMap { fix(for: $0, latitude: latitude, longitude: longitude, at: date) }
    }

    /// The satellite currently above the horizon that is closest to the observer
    /// (smallest range). nil if none are up.
    func closestUp(latitude: Double, longitude: Double, at date: Date) -> Fix? {
        allFixes(latitude: latitude, longitude: longitude, at: date)
            .filter { $0.isUp }
            .min { $0.rangeKm < $1.rangeKm }
    }

    /// The soonest upcoming visible pass across all tracked satellites.
    func nextPass(latitude: Double, longitude: Double, from date: Date,
                  minAltitude: Double = 10, withinHours: Double = 24) -> Pass? {
        var best: Pass?
        for sat in satellites {
            if let p = scanPass(sat, latitude: latitude, longitude: longitude,
                                from: date, minAltitude: minAltitude, withinHours: withinHours) {
                if best == nil || p.start < best!.start { best = p }
            }
        }
        return best
    }

    private func scanPass(_ sat: Tracked, latitude: Double, longitude: Double,
                          from date: Date, minAltitude: Double, withinHours: Double) -> Pass? {
        let step = 30.0
        var t = date
        let end = date.addingTimeInterval(withinHours * 3600)
        var inPass = false
        var start: Date?
        var peak = -90.0, peakAz = 0.0
        while t < end {
            guard let f = fix(for: sat, latitude: latitude, longitude: longitude, at: t) else { return nil }
            if f.altitude >= minAltitude {
                if !inPass { inPass = true; start = t; peak = f.altitude; peakAz = f.azimuth }
                else if f.altitude > peak { peak = f.altitude; peakAz = f.azimuth }
            } else if inPass, let s = start {
                return Pass(name: sat.name, start: s, peakAltitude: peak, peakAzimuth: peakAz)
            }
            t = t.addingTimeInterval(step)
        }
        if inPass, let s = start { return Pass(name: sat.name, start: s, peakAltitude: peak, peakAzimuth: peakAz) }
        return nil
    }
}
