//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation

/// Stores the photographer's own capture presets — dial in settings that give a
/// good shot, save them, and they sit alongside the built-ins forever. Persisted
/// as JSON in UserDefaults (small, on-device, no account).
///
/// © Ankur Sinha.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var custom: [CapturePreset] = []

    private let key = "customCapturePresets"

    init() { load() }

    /// Built-ins first, then the user's saved presets.
    var all: [CapturePreset] { CapturePreset.all + custom }

    /// Save a new custom preset from the current capture settings.
    func save(name: String, iso: Float, shutterSeconds: Double,
              totalExposureSeconds: Double, zoom: Double, focusInfinity: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = CapturePreset(
            id: "custom.\(UUID().uuidString)",
            name: clean.isEmpty ? "My preset" : clean,
            sfSymbol: "star.fill",
            iso: iso, shutterSeconds: shutterSeconds,
            totalExposureSeconds: totalExposureSeconds,
            zoom: zoom, focusInfinity: focusInfinity,
            hint: "Your saved preset.")
        custom.append(preset)
        persist()
    }

    func delete(_ preset: CapturePreset) {
        custom.removeAll { $0.id == preset.id }
        persist()
    }

    /// Only user presets can be deleted (built-ins have fixed ids).
    func isCustom(_ preset: CapturePreset) -> Bool { preset.id.hasPrefix("custom.") }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CapturePreset].self, from: data) else { return }
        custom = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
