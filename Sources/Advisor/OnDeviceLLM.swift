import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(UIKit)
import UIKit
#endif

/// **OnDeviceLLM** — the optional Apple Intelligence layer. It uses Apple's
/// **Foundation Models framework** (iOS 26+, on-device, free, offline, no API
/// key) where the hardware supports it (iPhone 15 Pro / A17 Pro and newer — so
/// the iPhone 17 Pro reference device qualifies). Everywhere else it returns nil
/// and the app falls back to deterministic phrasing.
///
/// It **never decides** capture settings or image adjustments — those come from
/// the deterministic engines (`CaptureAdvisor`, `AutoDevelop`). The model only
/// *understands and narrates*: it restates the computed numbers naturally, and
/// (with image input) explains what a developed night-sky photo actually shows
/// and how it was captured. The math is the source of truth; the model phrases.
///
/// © Ankur Sinha. Custom code; the only dependency is Apple's own framework.
struct OnDeviceLLM {

    /// True when Apple's on-device model is available and ready on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    // MARK: - Capture advice phrasing (text only)

    /// Rephrase the advisor's recipe. Returns nil to fall back to deterministic
    /// phrasing (model unavailable or errored).
    func phrase(recipe: CaptureRecipe, conditions: SkyConditions) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), Self.isAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.systemPrompt)
                let reply = try await session.respond(to: Self.prompt(recipe, conditions))
                return reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: - Photo understanding (image input, WWDC26)

    /// Narrate what a *developed* night-sky photo shows and confirm how it was
    /// captured, from the deterministic `AutoDevelop` findings. The recovery
    /// numbers are already decided; the model only puts them in plain language.
    /// Returns nil to fall back to AutoDevelop's own deterministic explanation.
    ///
    /// Note: this grounds the model on AutoDevelop's measured findings (text).
    /// Attaching the raw pixels via Foundation Models' image-input API is a
    /// planned refinement; until then the deterministic measurements — mean
    /// luminance, ISO, exposure, stack — are the trustworthy source, and the
    /// model never guesses beyond them.
    func explainPhoto(autoFindings: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), Self.isAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.photoPrompt)
                let prompt = """
                A night-sky photo has been auto-developed. Measured findings:
                \(autoFindings)
                In two short sentences, say what such a shot typically reveals and
                confirm how it was captured. Do not name specific objects you
                cannot verify from the findings.
                """
                let reply = try await session.respond(to: prompt)
                return reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        _ = autoFindings
        return nil
    }

    // MARK: - Grounding prompts

    static let systemPrompt = """
    You are a concise night-sky photography assistant inside the Firmament app.
    You are given exact, already-computed capture settings and real sky
    conditions. Restate them in one short, friendly sentence. Never change the
    ISO, exposure, or stack count. Never invent objects, weather, or events not
    provided. If conditions are poor, say so plainly. One sentence only.
    """

    static let photoPrompt = """
    You are an astrophotography assistant inside the Firmament app. You explain,
    in plain language, what a night-sky photo shows and how it was captured. You
    are given the app's own measured technical findings — trust them for the
    numbers. Be accurate and humble: only name objects clearly visible, never
    guess. Keep it to two short sentences.
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
        return lines.joined(separator: "\n")
    }
}
