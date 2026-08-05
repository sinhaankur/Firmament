//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation

/// Fetches fresh Two-Line Element sets from **CelesTrak** (keyless, no account)
/// so satellite positions are current instead of drifting from the bundled TLE.
/// Results are cached on-device with a timestamp; if the network is unavailable
/// the app falls back to the bundled catalog and says so honestly.
///
/// © Ankur Sinha.
actor TLEService {
    static let shared = TLEService()

    struct Fetched {
        let tles: [SatelliteTLE]
        let updated: Date
    }

    private var cache: Fetched?
    /// Refresh at most every few hours — TLEs are re-issued roughly daily.
    private let ttl: TimeInterval = 6 * 3600

    /// Return fresh TLEs for the catalog's satellites, using cache within TTL.
    /// Falls back to the bundled catalog for any that fail.
    func current() async -> Fetched {
        if let c = cache, Date().timeIntervalSince(c.updated) < ttl {
            return c
        }
        var out: [SatelliteTLE] = []
        for bundled in SatelliteCatalog.bright {
            if let catnr = Self.catnr(for: bundled),
               let fresh = await fetch(catnr: catnr, fallbackName: bundled.name) {
                out.append(fresh)
            } else {
                out.append(bundled)   // keep the bundled one if fetch fails
            }
        }
        let result = Fetched(tles: out, updated: Date())
        cache = result
        return result
    }

    /// How long ago the cache was refreshed, for an honest "updated Xh ago" label.
    var lastUpdated: Date? { cache?.updated }

    // MARK: - Fetch one

    private func fetch(catnr: Int, fallbackName: String) async -> SatelliteTLE? {
        let urlStr = "https://celestrak.org/NORAD/elements/gp.php?CATNR=\(catnr)&FORMAT=TLE"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return Self.parseTLE(text, fallbackName: fallbackName)
        } catch {
            return nil
        }
    }

    /// Parse a 3-line TLE block (name + line1 + line2). CelesTrak returns the
    /// name on the first line; some responses omit it, so we fall back.
    static func parseTLE(_ text: String, fallbackName: String) -> SatelliteTLE? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Find the two element lines (start with "1 " and "2 ").
        guard let l1 = lines.first(where: { $0.hasPrefix("1 ") }),
              let l2 = lines.first(where: { $0.hasPrefix("2 ") }),
              l1.count >= 63, l2.count >= 63 else { return nil }
        let name = lines.first(where: { !$0.hasPrefix("1 ") && !$0.hasPrefix("2 ") }) ?? fallbackName
        return SatelliteTLE(name: name.isEmpty ? fallbackName : name, line1: l1, line2: l2)
    }

    /// Map a bundled satellite to its NORAD catalog number (from its TLE line 1).
    private static func catnr(for tle: SatelliteTLE) -> Int? {
        // Columns 3–7 of line 1 are the catalog number.
        let l1 = Array(tle.line1)
        guard l1.count > 7 else { return nil }
        let digits = String(l1[2..<7]).trimmingCharacters(in: .whitespaces)
        return Int(digits)
    }
}
