import Foundation

/// The top-level sky computer. Given an observer (lat/lon) and a time, it
/// resolves every catalog object into `SkyObject`s with current alt/az.
///
/// Everything is pure and synchronous — no I/O, no network. Callers feed it a
/// location from `LocationService` and a date (usually `Date()`), and get back
/// what's in the sky right now. This is the on-device, offline core.
struct SkyEngine {

    struct Observer {
        let latitude: Double
        let longitude: Double   // East positive
    }

    let observer: Observer

    // MARK: - Individual bodies

    func sun(at date: Date) -> SkyObject {
        let jd = SkyMath.julianDay(from: date)
        let s = SolarSystem.sun(jd: jd)
        let h = horizontal(raDeg: s.raDeg, decDeg: s.decDeg, jd: jd)
        return SkyObject(
            id: "sun", name: "Sun", kind: .sun,
            raDeg: s.raDeg, decDeg: s.decDeg,
            altitude: h.altitude, azimuth: h.azimuth,
            magnitude: -26.7,
            distanceText: String(format: "%.3f AU", s.distanceAU),
            blurb: "Our star. Never look at it directly."
        )
    }

    func moon(at date: Date) -> SkyObject {
        let jd = SkyMath.julianDay(from: date)
        let m = SolarSystem.moon(jd: jd)
        let phase = SolarSystem.moonPhase(jd: jd)
        let h = horizontal(raDeg: m.raDeg, decDeg: m.decDeg, jd: jd)
        return SkyObject(
            id: "moon", name: "Moon", kind: .moon,
            raDeg: m.raDeg, decDeg: m.decDeg,
            altitude: h.altitude, azimuth: h.azimuth,
            magnitude: -12.7,
            distanceText: String(format: "%.0f km", m.distanceKm),
            blurb: String(format: "%.0f%% illuminated.", phase.illumination * 100)
        )
    }

    func planets(at date: Date) -> [SkyObject] {
        let jd = SkyMath.julianDay(from: date)
        return Planet.visible.compactMap { p in
            guard let pos = SolarSystem.planet(p, jd: jd) else { return nil }
            let h = horizontal(raDeg: pos.raDeg, decDeg: pos.decDeg, jd: jd)
            return SkyObject(
                id: "planet.\(p.rawValue)", name: p.displayName, kind: .planet,
                raDeg: pos.raDeg, decDeg: pos.decDeg,
                altitude: h.altitude, azimuth: h.azimuth,
                magnitude: nil,
                distanceText: String(format: "%.2f AU", pos.distanceAU),
                blurb: nil
            )
        }
    }

    func stars(at date: Date) -> [SkyObject] {
        let jd = SkyMath.julianDay(from: date)
        return StarCatalog.bright.map { s in
            let h = horizontal(raDeg: s.raDeg, decDeg: s.decDeg, jd: jd)
            return SkyObject(
                id: "star.\(s.id)", name: s.name, kind: .star,
                raDeg: s.raDeg, decDeg: s.decDeg,
                altitude: h.altitude, azimuth: h.azimuth,
                magnitude: s.magnitude,
                distanceText: nil, blurb: nil
            )
        }
    }

    /// Everything at once. Optionally filter to objects above the horizon.
    func allObjects(at date: Date, aboveHorizonOnly: Bool = false) -> [SkyObject] {
        var out = [sun(at: date), moon(at: date)]
        out += planets(at: date)
        out += stars(at: date)
        return aboveHorizonOnly ? out.filter { $0.isAboveHorizon } : out
    }

    // MARK: - Helpers

    private func horizontal(raDeg: Double, decDeg: Double, jd: Double)
        -> (altitude: Double, azimuth: Double)
    {
        let h = SkyMath.equatorialToHorizontal(
            raDeg: raDeg, decDeg: decDeg,
            latitude: observer.latitude, longitude: observer.longitude,
            jd: jd
        )
        return (SkyMath.refractedAltitude(h.altitude), h.azimuth)
    }
}
