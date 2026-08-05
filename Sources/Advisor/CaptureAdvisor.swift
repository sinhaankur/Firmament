import Foundation
import Combine

/// **CaptureAdvisor** — recommends how to shoot the night sky *right now* from
/// real conditions (weather + Moon + darkness + this device's limits).
///
/// It is **model-free at its core**: a deterministic rule engine produces both a
/// concrete `CaptureRecipe` and a plain-language line, and works fully offline
/// with no LLM. A tiny on-device language model is an **optional phrasing layer
/// only** — it never decides the settings, it just says them more naturally, fed
/// the computed data at runtime. This mirrors the project rule: the math decides;
/// the LLM, if present, only phrases. Nothing here acts autonomously — the user
/// still taps the shutter.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
@MainActor
final class CaptureAdvisor: ObservableObject {
    /// One-line, human-readable recommendation for the capture UI.
    @Published var advice: String = ""
    /// The concrete settings the recommendation resolves to.
    @Published var recipe: CaptureRecipe?

    /// Recompute from the latest conditions + device profile.
    func update(conditions: SkyConditions?, profile: DeviceCaptureProfile?) {
        guard let conditions else {
            advice = ""; recipe = nil; return
        }
        let recipe = Self.recommend(for: conditions, profile: profile)
        self.recipe = recipe
        self.advice = Self.phrase(recipe, conditions)
    }

    // MARK: - Deterministic rule engine (the part that decides)

    static func recommend(for c: SkyConditions,
                          profile: DeviceCaptureProfile?) -> CaptureRecipe {
        // Start from a sensible night baseline, then adapt to conditions.
        var iso: Double = 3200
        var target: CaptureRecipe.Target = .stars
        var stack = profile?.suggestedStackFrames ?? 16
        var notes: [String] = []

        // Darkness: below astronomical twilight we can push for faint targets.
        if c.isAstronomicalNight {
            target = .deepSky
        } else if c.sunAltitude < -6 {
            target = .stars
            notes.append("still some twilight — wait for full dark for faint objects")
        } else {
            target = .brightOnly
            iso = 1600
            notes.append("sky isn't dark yet")
        }

        // Moon: a bright, risen Moon washes faint targets — favour Moon/planets.
        if c.moonIsWashing {
            target = target == .deepSky ? .moonAndPlanets : target
            iso = min(iso, 1600)
            notes.append("bright Moon up — shoot the Moon & planets, not faint sky")
        }

        // Clouds: if it's not clear, say so honestly.
        if !c.isClearish {
            notes.append("cloud cover is high — the sky may not cooperate")
        }

        // Wind: long stacks suffer if the tripod shakes.
        if let w = c.windSpeed, w > 6 {
            stack = max(4, stack / 2)
            notes.append("windy — shorter stack to avoid smearing")
        }

        // Temperature: warm sensors are noisier; ease ISO down a touch.
        if let t = c.temperatureC, t > 25 {
            iso = min(iso, 2500)
            notes.append("warm night — sensor noise up, keeping ISO modest")
        }

        // Exposure comes from what the device honestly allows.
        let maxExp = profile?.maxExposureSeconds ?? 1.0
        let exposure = min(maxExp, target == .moonAndPlanets ? 0.1 : maxExp)

        return CaptureRecipe(
            target: target,
            isoRecommendation: Int(iso),
            exposureSeconds: exposure,
            stackFrames: stack,
            useTripod: target != .moonAndPlanets,
            notes: notes
        )
    }

    // MARK: - Phrasing (the optional, replaceable part)

    /// Deterministic phrasing. An on-device LLM (Apple Foundation Models, when
    /// wired) can override this by consuming the same `recipe` + `conditions` —
    /// but the default needs no model and always works.
    static func phrase(_ r: CaptureRecipe, _ c: SkyConditions) -> String {
        let lead: String
        switch r.target {
        case .deepSky:        lead = "Great deep-sky window"
        case .stars:          lead = "Good for stars & constellations"
        case .moonAndPlanets: lead = "Best for the Moon & planets tonight"
        case .brightOnly:     lead = "Only the brightest objects for now"
        }
        let settings = String(
            format: "ISO %d · %@ · ×%d",
            r.isoRecommendation, r.exposureText, r.stackFrames)
        if let first = r.notes.first {
            return "\(lead). \(settings) — \(first)."
        }
        return "\(lead). \(settings)."
    }
}

/// A concrete, actionable set of capture settings.
struct CaptureRecipe {
    enum Target { case deepSky, stars, moonAndPlanets, brightOnly }
    let target: Target
    let isoRecommendation: Int
    let exposureSeconds: Double
    let stackFrames: Int
    let useTripod: Bool
    let notes: [String]

    var exposureText: String {
        exposureSeconds >= 1
            ? String(format: "%.0fs", exposureSeconds)
            : String(format: "%.0fms", exposureSeconds * 1000)
    }
}
