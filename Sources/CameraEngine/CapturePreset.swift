import Foundation

/// One-tap subject presets. Each bundles the right starting point for a kind of
/// night shot — ISO, shutter, how many frames to stack (total integration),
/// zoom, and focus — so a photographer goes from cold-fingered slider-fiddling
/// to "tap Milky Way, shoot."
///
/// Values are honest astrophotography starting points; when applied they're
/// clamped to the device's real limits. They're a *starting point*, not a
/// straitjacket — every control stays adjustable afterwards.
///
/// © Ankur Sinha.
struct CapturePreset: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let sfSymbol: String
    /// Suggested ISO.
    let iso: Float
    /// Per-frame shutter (seconds); clamped to the hardware max on apply.
    let shutterSeconds: Double
    /// Target total integration time (seconds) achieved by stacking. 0 = single.
    let totalExposureSeconds: Double
    /// Zoom factor (1 = native wide).
    let zoom: Double
    /// Focus at infinity (true) vs. leave to autofocus (false).
    let focusInfinity: Bool
    /// A one-line "why these settings" for the UI.
    let hint: String

    static let all: [CapturePreset] = [
        CapturePreset(
            id: "milkyway", name: "Milky Way", sfSymbol: "sparkles",
            iso: 3200, shutterSeconds: 1.0, totalExposureSeconds: 30, zoom: 1,
            focusInfinity: true,
            hint: "Wide, high ISO, ~30s stacked — pull the galactic core out of the dark."),
        CapturePreset(
            id: "moon", name: "Moon", sfSymbol: "moon.fill",
            iso: 100, shutterSeconds: 0.008, totalExposureSeconds: 0, zoom: 5,
            focusInfinity: true,
            hint: "The Moon is BRIGHT — low ISO, fast shutter, zoomed in for detail."),
        CapturePreset(
            id: "trails", name: "Star Trails", sfSymbol: "hurricane",
            iso: 800, shutterSeconds: 1.0, totalExposureSeconds: 240, zoom: 1,
            focusInfinity: true,
            hint: "Long total integration — the stars streak into arcs around the pole."),
        CapturePreset(
            id: "planets", name: "Planets", sfSymbol: "circle.circle",
            iso: 400, shutterSeconds: 0.033, totalExposureSeconds: 0, zoom: 5,
            focusInfinity: true,
            hint: "Bright points — modest ISO, short shutter, zoomed for the disk."),
        CapturePreset(
            id: "iss", name: "ISS / Sat", sfSymbol: "dot.radiowaves.up.forward",
            iso: 1600, shutterSeconds: 1.0, totalExposureSeconds: 8, zoom: 1,
            focusInfinity: true,
            hint: "Catch the pass as a bright streak — a few short frames stacked."),
        CapturePreset(
            id: "aurora", name: "Aurora", sfSymbol: "cloud.moon",
            iso: 1600, shutterSeconds: 1.0, totalExposureSeconds: 8, zoom: 1,
            focusInfinity: true,
            hint: "Aurora moves — shorter total exposure keeps the curtains crisp."),
    ]
}
