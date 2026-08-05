import Foundation

/// Low-precision positions for the Sun, Moon, and naked-eye planets.
///
/// The Sun uses Meeus ch.25 (apparent geocentric), the Moon uses the abridged
/// ch.47 series, and the planets use a compact set of Keplerian elements with
/// linear rates (Standish / JPL "approximate positions" model). Accuracy is a
/// few arc-minutes for the planets over 1800–2050 — invisible at naked-eye
/// pointing scale, and clearly the right tool for a phone in the field rather
/// than a 133 MB ephemeris.
enum SolarSystem {

    // MARK: - Sun (geocentric apparent RA/Dec)

    static func sun(jd: Double) -> (raDeg: Double, decDeg: Double, distanceAU: Double) {
        let t = SkyMath.julianCenturies(jd)
        let l0 = SkyMath.norm360(280.46646 + t * (36000.76983 + t * 0.0003032))
        let m = SkyMath.norm360(357.52911 + t * (35999.05029 - t * 0.0001537))
        let mRad = SkyMath.deg2rad(m)
        let c = (1.914602 - t * (0.004817 + 0.000014 * t)) * sin(mRad)
            + (0.019993 - 0.000101 * t) * sin(2 * mRad)
            + 0.000289 * sin(3 * mRad)
        let trueLon = l0 + c
        let trueAnom = m + c
        let r = 1.000001018 * (1 - 0.01671123 * cos(SkyMath.deg2rad(trueAnom)))
        // apparent longitude (nutation + aberration, abbreviated)
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLon - 0.00569 - 0.00478 * sin(SkyMath.deg2rad(omega))
        let eq = SkyMath.eclipticToEquatorial(lonDeg: lambda, latDeg: 0, jd: jd)
        return (eq.raDeg, eq.decDeg, r)
    }

    // MARK: - Moon (abridged ELP)

    static func moon(jd: Double) -> (raDeg: Double, decDeg: Double, distanceKm: Double) {
        let t = SkyMath.julianCenturies(jd)
        func d2r(_ x: Double) -> Double { SkyMath.deg2rad(SkyMath.norm360(x)) }

        let lp = 218.3164477 + 481267.88123421 * t   // mean longitude
        let d  = 297.8501921 + 445267.1114034 * t    // mean elongation
        let m  = 357.5291092 + 35999.0502909 * t     // sun mean anomaly
        let mp = 134.9633964 + 477198.8675055 * t    // moon mean anomaly
        let f  = 93.2720950 + 483202.0175233 * t     // argument of latitude

        let D = d2r(d), M = d2r(m), MP = d2r(mp), F = d2r(f)

        // Longitude (deg) — leading terms
        let lon = lp
            + 6.288774 * sin(MP)
            + 1.274027 * sin(2 * D - MP)
            + 0.658314 * sin(2 * D)
            + 0.213618 * sin(2 * MP)
            - 0.185116 * sin(M)
            - 0.114332 * sin(2 * F)
            + 0.058793 * sin(2 * D - 2 * MP)
            + 0.057066 * sin(2 * D - M - MP)
            + 0.053322 * sin(2 * D + MP)
            + 0.045758 * sin(2 * D - M)

        // Latitude (deg) — leading terms
        let lat = 5.128122 * sin(F)
            + 0.280602 * sin(MP + F)
            + 0.277693 * sin(MP - F)
            + 0.173237 * sin(2 * D - F)
            + 0.055413 * sin(2 * D + F - MP)
            + 0.046271 * sin(2 * D - F - MP)

        // Distance (km)
        let dist = 385000.56
            - 20905.355 * cos(MP)
            - 3699.111 * cos(2 * D - MP)
            - 2955.968 * cos(2 * D)
            - 569.925 * cos(2 * MP)

        let eq = SkyMath.eclipticToEquatorial(lonDeg: lon, latDeg: lat, jd: jd)
        return (eq.raDeg, eq.decDeg, dist)
    }

    /// Illuminated fraction of the Moon's disk (0…1) and a 0…1 phase
    /// (0=new, 0.5=full).
    static func moonPhase(jd: Double) -> (illumination: Double, phase: Double) {
        let s = sun(jd: jd)
        let m = moon(jd: jd)
        let sunRA = SkyMath.deg2rad(s.raDeg), sunDec = SkyMath.deg2rad(s.decDeg)
        let mRA = SkyMath.deg2rad(m.raDeg), mDec = SkyMath.deg2rad(m.decDeg)
        let cosElong = sin(sunDec) * sin(mDec)
            + cos(sunDec) * cos(mDec) * cos(sunRA - mRA)
        let elong = acos(max(-1, min(1, cosElong)))
        let illum = (1 - cos(elong)) / 2
        let phase = elong / (2 * .pi)
        return (illum, phase)
    }

    // MARK: - Planets (Keplerian, Standish approximate)

    struct KeplerElements {
        let a0, aRate: Double       // semi-major axis (AU) + rate/century
        let e0, eRate: Double       // eccentricity
        let i0, iRate: Double       // inclination (deg)
        let L0, LRate: Double       // mean longitude (deg)
        let wbar0, wbarRate: Double // longitude of perihelion (deg)
        let om0, omRate: Double     // longitude of ascending node (deg)
    }

    /// J2000 elements + rates per Julian century (JPL, valid 1800–2050).
    /// Earth is present so planets can be converted to a geocentric view; it is
    /// never rendered as a sky label (see `Planet.visible`).
    static let planetElements: [Planet: KeplerElements] = [
        .earth:   .init(a0: 1.00000261, aRate: 0.00000562, e0: 0.01671123, eRate: -0.00004392,
                        i0: -0.00001531, iRate: -0.01294668, L0: 100.46457166, LRate: 35999.37244981,
                        wbar0: 102.93768193, wbarRate: 0.32327364, om0: 0.0, omRate: 0.0),
        .mercury: .init(a0: 0.38709927, aRate: 0.00000037, e0: 0.20563593, eRate: 0.00001906,
                        i0: 7.00497902, iRate: -0.00594749, L0: 252.25032350, LRate: 149472.67411175,
                        wbar0: 77.45779628, wbarRate: 0.16047689, om0: 48.33076593, omRate: -0.12534081),
        .venus:   .init(a0: 0.72333566, aRate: 0.00000390, e0: 0.00677672, eRate: -0.00004107,
                        i0: 3.39467605, iRate: -0.00078890, L0: 181.97909950, LRate: 58517.81538729,
                        wbar0: 131.60246718, wbarRate: 0.00268329, om0: 76.67984255, omRate: -0.27769418),
        .mars:    .init(a0: 1.52371034, aRate: 0.00001847, e0: 0.09339410, eRate: 0.00007882,
                        i0: 1.84969142, iRate: -0.00813131, L0: -4.55343205, LRate: 19140.30268499,
                        wbar0: -23.94362959, wbarRate: 0.44441088, om0: 49.55953891, omRate: -0.29257343),
        .jupiter: .init(a0: 5.20288700, aRate: -0.00011607, e0: 0.04838624, eRate: -0.00013253,
                        i0: 1.30439695, iRate: -0.00183714, L0: 34.39644051, LRate: 3034.74612775,
                        wbar0: 14.72847983, wbarRate: 0.21252668, om0: 100.47390909, omRate: 0.20469106),
        .saturn:  .init(a0: 9.53667594, aRate: -0.00125060, e0: 0.05386179, eRate: -0.00050991,
                        i0: 2.48599187, iRate: 0.00193609, L0: 49.95424423, LRate: 1222.49362201,
                        wbar0: 92.59887831, wbarRate: -0.41897216, om0: 113.66242448, omRate: -0.28867794),
        .uranus:  .init(a0: 19.18916464, aRate: -0.00196176, e0: 0.04725744, eRate: -0.00004397,
                        i0: 0.77263783, iRate: -0.00242939, L0: 313.23810451, LRate: 428.48202785,
                        wbar0: 170.95427630, wbarRate: 0.40805281, om0: 74.01692503, omRate: 0.04240589),
        .neptune: .init(a0: 30.06992276, aRate: 0.00026291, e0: 0.00859048, eRate: 0.00005105,
                        i0: 1.77004347, iRate: 0.00035372, L0: -55.12002969, LRate: 218.45945325,
                        wbar0: 44.96476227, wbarRate: -0.32241464, om0: 131.78422574, omRate: -0.00508664),
    ]

    /// Heliocentric ecliptic rectangular coordinates for a planet (AU).
    private static func helioXYZ(_ p: Planet, t: Double) -> (Double, Double, Double)? {
        guard let el = planetElements[p] else { return nil }
        let a = el.a0 + el.aRate * t
        let e = el.e0 + el.eRate * t
        let i = SkyMath.deg2rad(el.i0 + el.iRate * t)
        let L = el.L0 + el.LRate * t
        let wbar = el.wbar0 + el.wbarRate * t
        let om = el.om0 + el.omRate * t

        let w = SkyMath.deg2rad(wbar - om)                 // argument of perihelion
        var M = SkyMath.deg2rad(SkyMath.norm360(L - wbar)) // mean anomaly
        if M > .pi { M -= 2 * .pi }

        // Solve Kepler's equation for eccentric anomaly E.
        var E = M + e * sin(M)
        for _ in 0..<8 {
            let dE = (E - e * sin(E) - M) / (1 - e * cos(E))
            E -= dE
            if abs(dE) < 1e-9 { break }
        }

        // Position in orbital plane.
        let xv = a * (cos(E) - e)
        let yv = a * (sqrt(1 - e * e) * sin(E))

        let node = SkyMath.deg2rad(om)
        let cosO = cos(node), sinO = sin(node)
        let cosI = cos(i), sinI = sin(i)
        let cosW = cos(w), sinW = sin(w)

        let x = (cosO * cosW - sinO * sinW * cosI) * xv
              + (-cosO * sinW - sinO * cosW * cosI) * yv
        let y = (sinO * cosW + cosO * sinW * cosI) * xv
              + (-sinO * sinW + cosO * cosW * cosI) * yv
        let z = (sinW * sinI) * xv + (cosW * sinI) * yv
        return (x, y, z)
    }

    /// Geocentric apparent RA/Dec (deg) + Earth distance (AU) for a planet.
    static func planet(_ p: Planet, jd: Double) -> (raDeg: Double, decDeg: Double, distanceAU: Double)? {
        let t = SkyMath.julianCenturies(jd)
        guard let (px, py, pz) = helioXYZ(p, t: t),
              let (ex, ey, ez) = helioXYZ(.earth, t: t) else { return nil }
        let x = px - ex, y = py - ey, z = pz - ez
        let dist = sqrt(x * x + y * y + z * z)

        // Ecliptic lon/lat of the geocentric vector.
        let lon = SkyMath.rad2deg(atan2(y, x))
        let lat = SkyMath.rad2deg(atan2(z, sqrt(x * x + y * y)))
        let eq = SkyMath.eclipticToEquatorial(lonDeg: lon, latDeg: lat, jd: jd)
        return (eq.raDeg, eq.decDeg, dist)
    }
}
