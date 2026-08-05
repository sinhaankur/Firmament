import Foundation

/// A compact SGP4 propagator — the standard model for tracking Earth-orbit
/// satellites from a Two-Line Element set. LEO satellites like the ISS move too
/// fast and are perturbed too much for the Keplerian planet model, so this is
/// the honest tool for them.
///
/// This implements the core SGP4 (near-Earth) path from the Spacetrack Report #3
/// / Vallado formulation, sufficient for pointing at the ISS. It is intentionally
/// self-contained (no third-party library), and where the deep-space (SDP4)
/// terms would be needed for high orbits, this near-Earth path is the correct
/// choice for the ISS's ~420 km altitude.
///
/// © Ankur Sinha. Custom implementation of the public SGP4 algorithm.
struct SGP4 {

    // WGS-72 constants (the set SGP4/TLEs are defined against).
    private static let mu = 398600.8            // km^3/s^2
    private static let earthRadius = 6378.135   // km
    private static let xke = 60.0 / sqrt(earthRadius * earthRadius * earthRadius / mu)
    private static let tothrd = 2.0 / 3.0
    private static let j2 = 0.001082616
    private static let j3 = -0.00000253881
    private static let j4 = -0.00000165597
    private static let ck2 = 0.5 * j2
    private static let ck4 = -0.375 * j4
    private static let qoms2t = 1.88027916e-9
    private static let s = 1.01222928

    // Parsed TLE elements (mean, at epoch).
    let epochJD: Double
    private let bstar: Double
    private let inclo: Double     // inclination (rad)
    private let nodeo: Double     // RAAN (rad)
    private let ecco: Double      // eccentricity
    private let argpo: Double     // arg of perigee (rad)
    private let mo: Double        // mean anomaly (rad)
    private let no: Double        // mean motion (rad/min)

    // Derived at init.
    private let aodp, xnodp, cosio, sinio, eta, c1, c4, xmdot, omgdot, xnodot, xnodcf, t2cof, xlcof, aycof, delmo, sinmo, x1mth2, x7thm1: Double

    /// Position + velocity in the TEME (True Equator Mean Equinox) frame, km.
    struct StateVector { let x, y, z, vx, vy, vz: Double }

    init?(line1: String, line2: String) {
        // --- Parse the two lines ---
        func d(_ s: Substring) -> Double { Double(s.trimmingCharacters(in: .whitespaces)) ?? 0 }
        let l1 = Array(line1), l2 = Array(line2)
        guard l1.count >= 63, l2.count >= 63 else { return nil }

        // Epoch: columns 19-32 of line 1 (YYDDD.DDDDDDDD).
        let epochStr = String(line1[line1.index(line1.startIndex, offsetBy: 18)..<line1.index(line1.startIndex, offsetBy: 32)])
        let epYear = Int(epochStr.prefix(2)) ?? 0
        let epDay = Double(epochStr.dropFirst(2)) ?? 0
        let fullYear = epYear < 57 ? 2000 + epYear : 1900 + epYear
        epochJD = SGP4.julianDayOfYear(year: fullYear, dayOfYear: epDay)

        // BSTAR: columns 54-61, implied decimal + exponent.
        let bstarStr = String(line1[line1.index(line1.startIndex, offsetBy: 53)..<line1.index(line1.startIndex, offsetBy: 61)])
        bstar = SGP4.parseExp(bstarStr)

        // Line 2 fields (fixed columns).
        func f2(_ a: Int, _ b: Int) -> Double {
            d(line2[line2.index(line2.startIndex, offsetBy: a)..<line2.index(line2.startIndex, offsetBy: b)])
        }
        let deg2rad = Double.pi / 180
        inclo = f2(8, 16) * deg2rad
        nodeo = f2(17, 25) * deg2rad
        ecco = Double("0." + line2[line2.index(line2.startIndex, offsetBy: 26)..<line2.index(line2.startIndex, offsetBy: 33)].trimmingCharacters(in: .whitespaces)) ?? 0
        argpo = f2(34, 42) * deg2rad
        mo = f2(43, 51) * deg2rad
        let noRevPerDay = f2(52, 63)
        no = noRevPerDay * 2 * .pi / 1440.0    // rad/min

        // --- Recover original mean motion + semi-major axis (SGP4 init) ---
        let a1 = pow(SGP4.xke / no, SGP4.tothrd)
        cosio = cos(inclo)
        sinio = sin(inclo)
        let theta2 = cosio * cosio
        x1mth2 = 1 - theta2
        x7thm1 = 7 * theta2 - 1
        let eosq = ecco * ecco
        let betao2 = 1 - eosq
        let betao = sqrt(betao2)
        let del1 = 1.5 * SGP4.ck2 * (3 * theta2 - 1) / (a1 * a1 * betao * betao2)
        let ao = a1 * (1 - del1 * (0.5 * SGP4.tothrd + del1 * (1 + 134.0 / 81.0 * del1)))
        let delo = 1.5 * SGP4.ck2 * (3 * theta2 - 1) / (ao * ao * betao * betao2)
        xnodp = no / (1 + delo)
        aodp = ao / (1 - delo)

        // For perigee < 156 km, s and qoms2t are adjusted; ISS is fine with defaults.
        let s4 = SGP4.s
        let qoms24 = SGP4.qoms2t
        let perigee = (aodp * (1 - ecco) - 1) * SGP4.earthRadius
        let tsi = 1 / (aodp - s4)
        eta = aodp * ecco * tsi
        let etasq = eta * eta
        let eeta = ecco * eta
        let psisq = abs(1 - etasq)
        let coef = qoms24 * pow(tsi, 4)
        let coef1 = coef / pow(psisq, 3.5)
        let c2 = coef1 * xnodp * (aodp * (1 + 1.5 * etasq + eeta * (4 + etasq))
            + 0.75 * SGP4.ck2 * tsi / psisq * (3 * theta2 - 1) * (8 + 3 * etasq * (8 + etasq)))
        c1 = bstar * c2
        let x3thm1 = 3 * theta2 - 1
        let c1sq = c1 * c1
        let tsisq = tsi * tsi
        _ = perigee; _ = tsisq

        let a3ovk2 = -SGP4.j3 / SGP4.ck2 * 1.0
        c4 = 2 * xnodp * coef1 * aodp * betao2 * (eta * (2 + 0.5 * etasq)
            + ecco * (0.5 + 2 * etasq)
            - 2 * SGP4.ck2 * tsi / (aodp * psisq)
            * (-3 * x3thm1 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
               + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * cos(2 * argpo)))

        let theta4 = theta2 * theta2
        let pinvsq = 1 / (aodp * aodp * betao2 * betao2)
        let temp1 = 3 * SGP4.ck2 * pinvsq * xnodp
        let temp2 = temp1 * SGP4.ck2 * pinvsq
        let temp3 = 1.25 * SGP4.ck4 * pinvsq * pinvsq * xnodp
        xmdot = xnodp + 0.5 * temp1 * betao * x3thm1
            + 0.0625 * temp2 * betao * (13 - 78 * theta2 + 137 * theta4)
        let x1m5th = 1 - 5 * theta2
        omgdot = -0.5 * temp1 * x1m5th
            + 0.0625 * temp2 * (7 - 114 * theta2 + 395 * theta4)
            + temp3 * (3 - 36 * theta2 + 49 * theta4)
        let xhdot1 = -temp1 * cosio
        xnodot = xhdot1 + (0.5 * temp2 * (4 - 19 * theta2) + 2 * temp3 * (3 - 7 * theta2)) * cosio
        xnodcf = 3.5 * betao2 * xhdot1 * c1
        t2cof = 1.5 * c1
        xlcof = 0.125 * a3ovk2 * sinio * (3 + 5 * cosio) / (1 + cosio)
        aycof = 0.25 * a3ovk2 * sinio
        delmo = pow(1 + eta * cos(mo), 3)
        sinmo = sin(mo)
    }

    /// Propagate to `minutesSinceEpoch` and return the TEME state vector.
    func propagate(minutesSinceEpoch tsince: Double) -> StateVector {
        let xmdf = mo + xmdot * tsince
        let omgadf = argpo + omgdot * tsince
        let xnoddf = nodeo + xnodot * tsince
        let tsq = tsince * tsince
        let xnode = xnoddf + xnodcf * tsq
        let tempa = 1 - c1 * tsince
        let tempe = bstar * c4 * tsince
        let templ = t2cof * tsq

        let a = aodp * tempa * tempa
        let e = max(1e-6, ecco - tempe)
        let xl = xmdf + omgadf + xnode + xnodp * templ

        let beta = sqrt(1 - e * e)
        let xn = SGP4.xke / pow(a, 1.5)

        // Long-period periodics.
        let axn = e * cos(omgadf)
        let temp0 = 1 / (a * beta * beta)
        let xll = temp0 * xlcof * axn
        let aynl = temp0 * aycof
        let xlt = xl + xll
        let ayn = e * sin(omgadf) + aynl

        // Solve Kepler's equation for (E + ω).
        let capu = (xlt - xnode).truncatingRemainder(dividingBy: 2 * .pi)
        var epw = capu
        var sinepw = 0.0, cosepw = 0.0
        for _ in 0..<10 {
            sinepw = sin(epw); cosepw = cos(epw)
            let ecosE = axn * cosepw + ayn * sinepw
            let esinE = axn * sinepw - ayn * cosepw
            let f = capu - epw + esinE
            let df = 1 - ecosE
            let dpw = f / df
            epw += max(-0.95, min(0.95, dpw))
            if abs(dpw) < 1e-10 { break }
        }

        // Short-period preliminary quantities.
        let ecosE = axn * cosepw + ayn * sinepw
        let esinE = axn * sinepw - ayn * cosepw
        let elsq = axn * axn + ayn * ayn
        let pl = a * (1 - elsq)
        let r = a * (1 - ecosE)
        let rdot = SGP4.xke * sqrt(a) / r * esinE
        let rfdot = SGP4.xke * sqrt(pl) / r
        let temp = esinE / (1 + sqrt(1 - elsq))
        let sinu = a / r * (sinepw - ayn - axn * temp)
        let cosu = a / r * (cosepw - axn + ayn * temp)
        let u = atan2(sinu, cosu)
        let sin2u = 2 * sinu * cosu
        let cos2u = 2 * cosu * cosu - 1

        let temp1 = SGP4.ck2 / pl
        let temp2 = temp1 / pl
        // Apply short-period perturbations to the radius.
        let rkFinal = r * (1 - 1.5 * temp2 * beta * (3 * cosio * cosio - 1)) + 0.5 * temp1 * x1mth2 * cos2u
        let uk = u - 0.25 * temp2 * x7thm1 * sin2u
        let xnodek = xnode + 1.5 * temp2 * cosio * sin2u
        let xinck = inclo + 1.5 * temp2 * cosio * sinio * cos2u

        // Orientation vectors.
        let sinuk = sin(uk), cosuk = cos(uk)
        let sinnok = sin(xnodek), cosnok = cos(xnodek)
        let sinik = sin(xinck), cosik = cos(xinck)
        let xmx = -sinnok * cosik
        let xmy = cosnok * cosik
        let ux = xmx * sinuk + cosnok * cosuk
        let uy = xmy * sinuk + sinnok * cosuk
        let uz = sinik * sinuk
        let vx = xmx * cosuk - cosnok * sinuk
        let vy = xmy * cosuk - sinnok * sinuk
        let vz = sinik * cosuk

        let rKm = rkFinal * SGP4.earthRadius
        let rdotKm = rdot * SGP4.earthRadius / 60.0        // km/s
        let rfdotKm = rfdot * SGP4.earthRadius / 60.0

        return StateVector(
            x: rKm * ux, y: rKm * uy, z: rKm * uz,
            vx: rdotKm * ux + rfdotKm * vx,
            vy: rdotKm * uy + rfdotKm * vy,
            vz: rdotKm * uz + rfdotKm * vz
        )
    }

    // MARK: - Helpers

    private static func julianDayOfYear(year: Int, dayOfYear: Double) -> Double {
        // JD of Jan 0.0 of the year + dayOfYear.
        let y = year - 1
        let janZero = Double(367 * year - (7 * (year + (1 + 9) / 12)) / 4
            + (275 * 1) / 9 + 1) + 1721013.5 - 1
        _ = y
        // Simpler: JD at start of year (Jan 1 00:00) then add (dayOfYear-1).
        let a = (year - 1) / 100
        let b = 2 - a + a / 4
        let jdJan1 = floor(365.25 * Double(year - 1)) + floor(30.6001 * 14.0)
            + 1 + 1720994.5 + Double(b)
        _ = janZero
        return jdJan1 + (dayOfYear - 1)
    }

    private static func parseExp(_ s: String) -> Double {
        // Format like " 12345-3" → 0.12345e-3, or "-11606-4".
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return 0 }
        var sign = 1.0
        var body = t
        if body.hasPrefix("-") { sign = -1; body.removeFirst() }
        else if body.hasPrefix("+") { body.removeFirst() }
        // Last 1-2 chars are the exponent (with sign).
        guard let expSignIdx = body.lastIndex(where: { $0 == "-" || $0 == "+" }) else {
            return sign * (Double("0." + body) ?? 0)
        }
        let mantissa = String(body[body.startIndex..<expSignIdx])
        let expPart = String(body[expSignIdx...])
        let mant = Double("0." + mantissa) ?? 0
        let exp = Double(expPart) ?? 0
        return sign * mant * pow(10.0, exp)
    }
}
