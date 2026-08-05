//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation

/// Core astronomical math for turning a place + time + celestial coordinate
/// into a direction in the observer's sky (altitude / azimuth).
///
/// Formulas follow Jean Meeus, *Astronomical Algorithms*. Precision is
/// "naked-eye pointing" grade — more than enough to put a label on the right
/// star, well short of ephemeris-server accuracy. Where that trade-off matters
/// it is called out; nothing here is presented as more exact than it is.
enum SkyMath {

    // MARK: - Angles

    static func deg2rad(_ d: Double) -> Double { d * .pi / 180.0 }
    static func rad2deg(_ r: Double) -> Double { r * 180.0 / .pi }

    /// Normalize an angle in degrees to [0, 360).
    static func norm360(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360.0)
        return m < 0 ? m + 360.0 : m
    }

    // MARK: - Time

    /// Julian Day for a given date (UT).
    static func julianDay(from date: Date) -> Double {
        // Seconds since Unix epoch → JD. 2440587.5 is JD of 1970-01-01T00:00Z.
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Julian centuries since J2000.0.
    static func julianCenturies(_ jd: Double) -> Double {
        (jd - 2451545.0) / 36525.0
    }

    /// Greenwich Mean Sidereal Time in degrees (Meeus 12.4).
    static func gmstDegrees(_ jd: Double) -> Double {
        let t = julianCenturies(jd)
        var gmst = 280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * t * t
            - (t * t * t) / 38710000.0
        gmst = norm360(gmst)
        return gmst
    }

    /// Local Apparent Sidereal Time (degrees) — GMST corrected for longitude.
    /// East longitude positive.
    static func lstDegrees(jd: Double, longitudeEast: Double) -> Double {
        norm360(gmstDegrees(jd) + longitudeEast)
    }

    /// Obliquity of the ecliptic (degrees), Meeus 22.2 (mean).
    static func obliquityDegrees(_ jd: Double) -> Double {
        let t = julianCenturies(jd)
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        return 23.0 + (26.0 + seconds / 60.0) / 60.0
    }

    // MARK: - Coordinate transforms

    /// Ecliptic (lon/lat, degrees) → Equatorial (RA/Dec, degrees).
    static func eclipticToEquatorial(lonDeg: Double, latDeg: Double, jd: Double)
        -> (raDeg: Double, decDeg: Double)
    {
        let eps = deg2rad(obliquityDegrees(jd))
        let l = deg2rad(lonDeg)
        let b = deg2rad(latDeg)

        let sinDec = sin(b) * cos(eps) + cos(b) * sin(eps) * sin(l)
        let dec = asin(sinDec)

        let y = sin(l) * cos(eps) - tan(b) * sin(eps)
        let x = cos(l)
        var ra = atan2(y, x)
        if ra < 0 { ra += 2 * .pi }

        return (norm360(rad2deg(ra)), rad2deg(dec))
    }

    /// Equatorial (RA/Dec, degrees) → Horizontal (alt/az, degrees).
    /// Azimuth measured from North, increasing toward East (0=N, 90=E, 180=S).
    static func equatorialToHorizontal(
        raDeg: Double, decDeg: Double,
        latitude: Double, longitude: Double,
        jd: Double
    ) -> (altitude: Double, azimuth: Double) {
        let lst = lstDegrees(jd: jd, longitudeEast: longitude)
        let haDeg = norm360(lst - raDeg)          // local hour angle
        let ha = deg2rad(haDeg)
        let dec = deg2rad(decDeg)
        let lat = deg2rad(latitude)

        let sinAlt = sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(ha)
        let alt = asin(sinAlt)

        // Azimuth from North, clockwise (through East).
        let y = -sin(ha)
        let x = tan(dec) * cos(lat) - sin(lat) * cos(ha)
        var az = atan2(y, x)
        if az < 0 { az += 2 * .pi }

        return (rad2deg(alt), rad2deg(az))
    }

    /// Simple atmospheric refraction correction (Bennett) — adds apparent
    /// altitude near the horizon. Input/output in degrees.
    static func refractedAltitude(_ trueAltDeg: Double) -> Double {
        guard trueAltDeg > -2 else { return trueAltDeg }
        let h = trueAltDeg
        let r = 1.02 / tan(deg2rad(h + 10.3 / (h + 5.11))) // arcminutes
        return trueAltDeg + r / 60.0
    }
}
