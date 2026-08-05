//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation

/// A body we can point at. Earth is included only because the planet ephemeris
/// needs Earth's heliocentric position to convert to a geocentric view; it is
/// never shown as a sky label.
enum Planet: String, CaseIterable, Hashable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune

    var displayName: String { rawValue.capitalized }

    /// Bodies we actually draw in the sky (Earth excluded).
    static var visible: [Planet] {
        [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]
    }
}

enum SkyObjectKind: String {
    case sun, moon, planet, star, satellite
}

/// A resolved object with its current place in *this* observer's sky.
struct SkyObject: Identifiable {
    let id: String
    let name: String
    let kind: SkyObjectKind
    /// Apparent right ascension / declination (degrees), for the current time.
    let raDeg: Double
    let decDeg: Double
    /// Horizontal position for the observer (degrees). Azimuth 0=N, 90=E.
    var altitude: Double
    var azimuth: Double
    /// Apparent visual magnitude if known (lower = brighter).
    let magnitude: Double?
    /// Free-form distance string for the info card (already unit-formatted).
    let distanceText: String?
    /// One-line "what am I looking at".
    let blurb: String?

    var isAboveHorizon: Bool { altitude > 0 }
}
