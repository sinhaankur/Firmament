import Foundation

/// **OnDeviceLLM** — an optional, on-device natural-language phrasing layer for
/// the capture advice. It never decides settings; it only rewrites the advisor's
/// already-computed `CaptureRecipe` + `SkyConditions` into a friendlier sentence.
///
/// Design:
///   • Fully **optional and opt-in**. If no model is present, the advisor's
///     deterministic phrasing is used and the app is unaffected.
///   • **On-device only** — the plan is Apple's Foundation Models (Apple
///     Intelligence) where available (iOS 26+, supported hardware). No cloud, no
///     account, no data leaves the phone.
///   • **Fed data at runtime, not trained.** The model receives the computed
///     numbers and conditions as context and paraphrases them — it can't invent
///     settings, because the numbers come from the rule engine.
///
/// Availability is gated behind a capability check so this compiles and runs on
/// every device; the actual model call is wired when the framework is enabled.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
struct OnDeviceLLM {

    /// Whether an on-device model is available and the user has opted in.
    /// Wired to `SystemLanguageModel.default.availability` when Foundation
    /// Models is enabled for the target; false today so we ship the deterministic
    /// path and never block on a model.
    static var isAvailable: Bool { false }

    /// Rephrase the advice. Returns nil to fall back to deterministic phrasing.
    ///
    /// When Foundation Models is enabled, the implementation becomes roughly:
    /// ```
    /// import FoundationModels
    /// let session = LanguageModelSession(instructions: Self.systemPrompt)
    /// let reply = try await session.respond(to: prompt(recipe, conditions))
    /// return reply.content
    /// ```
    /// with strict instructions to only restate the given numbers.
    func phrase(recipe: CaptureRecipe, conditions: SkyConditions) async -> String? {
        guard Self.isAvailable else { return nil }
        // Placeholder until Foundation Models is enabled for the target.
        return nil
    }

    /// The grounding instructions the model must obey: paraphrase only, never
    /// change the numbers, stay short, no invented facts.
    static let systemPrompt = """
    You are a concise night-sky photography assistant inside the NightSky app.
    You are given exact, already-computed capture settings and real sky
    conditions. Restate them in one short, friendly sentence. Never change the
    ISO, exposure, or stack count. Never invent objects, weather, or events not
    provided. If conditions are poor, say so plainly. One sentence only.
    """

    /// Build the user prompt from real data — the model paraphrases this.
    static func prompt(_ r: CaptureRecipe, _ c: SkyConditions) -> String {
        var lines = [
            "Target: \(r.target)",
            "ISO: \(r.isoRecommendation)",
            "Exposure: \(r.exposureText)",
            "Frames to stack: \(r.stackFrames)",
            "Moon illumination: \(Int(c.moonIllumination * 100))%",
            "Astronomical night: \(c.isAstronomicalNight)",
        ]
        if let cc = c.cloudCover { lines.append("Cloud cover: \(Int(cc * 100))%") }
        if let w = c.windSpeed { lines.append("Wind: \(Int(w)) m/s") }
        return lines.joined(separator: "\n")
    }
}
