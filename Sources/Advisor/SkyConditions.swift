import Foundation

/// A snapshot of the observing conditions the advisor reasons over. Every field
/// is real, measured or computed — nothing invented. Missing fields are left nil
/// and the advisor degrades gracefully rather than guessing.
///
/// © Ankur Sinha.
struct SkyConditions {
    /// Cloud cover 0…1 (0 = clear).
    var cloudCover: Double?
    /// Relative humidity 0…1.
    var humidity: Double?
    /// Moon illuminated fraction 0…1 (from NightSkyEngine, always available).
    var moonIllumination: Double
    /// Moon altitude in degrees (negative = below horizon, i.e. dark sky).
    var moonAltitude: Double
    /// Sun altitude in degrees (< -18 = astronomical night).
    var sunAltitude: Double
    /// Approximate Bortle-scale light pollution 1…9 if known (1 = pristine).
    var bortle: Int?
    /// Wind speed (m/s) — matters for tripod stability under long exposure.
    var windSpeed: Double?
    /// Ambient temperature (°C) — affects sensor noise.
    var temperatureC: Double?

    /// Is it dark enough for the deep sky (astronomical twilight passed)?
    var isAstronomicalNight: Bool { sunAltitude < -18 }
    /// Is the Moon up and bright enough to wash out faint targets?
    var moonIsWashing: Bool { moonAltitude > 0 && moonIllumination > 0.4 }
    /// Sky clear enough to bother?
    var isClearish: Bool { (cloudCover ?? 0) < 0.4 }
}
