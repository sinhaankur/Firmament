import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **OnDeviceLLM** — the optional Apple Intelligence layer, using Apple's
/// **Foundation Models framework** (iOS 26+, on-device, free, offline, no API
/// key) where the hardware supports it (iPhone 15 Pro / A17 Pro and newer). It
/// **never decides** capture settings or image adjustments — those come from the
/// deterministic engines; the model only *phrases* their output. Everywhere the
/// model is unavailable or slow, callers fall back to deterministic text.
///
/// Optimized for a phone:
///   • one **reused, prewarmed** session (warm start cuts first-token latency);
///   • **capped output** (`maximumResponseTokens`) + low temperature so replies
///     are short, fast, and stable;
///   • a **hard timeout** so the UI never waits on the model.
///
/// © Ankur Sinha. Custom code; the only dependency is Apple's own framework.
@MainActor
final class OnDeviceLLM {
    static let shared = OnDeviceLLM()

    /// True when Apple's on-device model is available and ready on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var session: LanguageModelSession? {
        if let s = _session as? LanguageModelSession { return s }
        guard Self.isAvailable else { return nil }
        let s = LanguageModelSession(instructions: Self.systemPrompt)
        s.prewarm()                 // warm the model so the first reply is quick
        _session = s
        return s
    }
    private var _session: AnyObject?

    @available(iOS 26.0, *)
    private var options: GenerationOptions {
        // Short, low-variance phrasing: this is a restater, not a storyteller.
        GenerationOptions(temperature: 0.4, maximumResponseTokens: 60)
    }
    #endif

    /// Warm the model ahead of first use (e.g. when Capture mode opens).
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { _ = session }
        #endif
    }

    // MARK: - Public entry points

    /// Rephrase the advisor's recipe. nil → deterministic fallback.
    func phrase(recipe: CaptureRecipe, conditions: SkyConditions) async -> String? {
        await run(prompt: Self.prompt(recipe, conditions))
    }

    /// Narrate a developed night-sky photo from AutoDevelop's measured findings.
    /// nil → deterministic fallback. The numbers are already decided; the model
    /// only puts them in plain language and never guesses beyond the findings.
    func explainPhoto(autoFindings: String) async -> String? {
        let prompt = """
        A night-sky photo has been auto-developed. Measured findings:
        \(autoFindings)
        In two short sentences, say what such a shot typically reveals and confirm
        how it was captured. Do not name objects you can't verify from the findings.
        """
        return await run(prompt: prompt)
    }

    // MARK: - Core (shared session + timeout)

    private func run(prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let session {
            let opts = options
            // Race the model against a timeout so the UI is never blocked.
            return await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    do {
                        let reply = try await session.respond(to: prompt, options: opts)
                        return reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch {
                        return nil
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 6_000_000_000) // 6s ceiling
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }
        #endif
        _ = prompt
        return nil
    }

    // MARK: - Grounding prompts

    static let systemPrompt = """
    You are a concise night-sky assistant inside the Firmament app. You are given
    exact, already-computed values (capture settings, sky conditions, or photo
    findings). Restate them in one or two short, friendly sentences. Never change
    a number. Never invent objects, weather, or events not provided. If conditions
    are poor, say so plainly.
    """

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
        return "Say this in one friendly sentence:\n" + lines.joined(separator: "\n")
    }
}
