//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation

/// A single star. Positions are J2000 right ascension / declination (degrees)
/// and apparent visual magnitude. Proper motion is ignored (negligible for
/// naked-eye pointing over decades).
struct Star: Identifiable {
    /// Stable identifier: the proper name if it has one, else "HYG-<index>".
    let id: String
    let raDeg: Double
    let decDeg: Double
    let magnitude: Double
    /// Colour index (B−V), for tinting; 0 if unknown.
    let colorIndex: Double
    /// Proper name if this star has one (Sirius, Vega, …), else nil.
    let properName: String?
    var name: String { properName ?? id }
}

/// The bundled star catalog. Loads the full naked-eye sky (~8,900 stars to
/// magnitude 6.5) from `stars.bin` — a compact binary derived from the **HYG
/// database** (Hipparcos + Yale + Gliese).
///
/// Attribution: HYG database by David Nash / astronexus.com, licensed
/// **CC BY-SA 4.0**. Firmament bundles a filtered, reformatted subset (naked-eye
/// stars, brightest-first) and credits it in the app's Settings → Data. This is
/// reference data, not code, and is redistributed under the same licence.
enum StarCatalog {

    /// All bundled stars (lazily loaded once, brightest-first).
    static let all: [Star] = loadStars()

    /// Named + bright stars, for constellation lookup and labeling. (Everything
    /// with a proper name plus everything brighter than mag 3.)
    static let bright: [Star] = all.filter { $0.properName != nil || $0.magnitude < 3.0 }

    /// Fast lookup of a star by its proper name (e.g. "Betelgeuse").
    static let byName: [String: Star] = {
        var d: [String: Star] = [:]
        for s in all { if let n = s.properName { d[n] = s } }
        return d
    }()

    static func star(named name: String) -> Star? { byName[name] }

    // MARK: - Binary loader

    /// Parse `stars.bin`. Format (little-endian): magic "FSTR", uint32 count,
    /// then per star: float32 ra, dec, mag, ci, uint8 nameLen, name bytes.
    private static func loadStars() -> [Star] {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 8 else {
            return fallback
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [Star] in
            var offset = 0
            func u8() -> UInt8 { defer { offset += 1 }; return raw[offset] }
            func u32() -> UInt32 {
                let v = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                offset += 4; return UInt32(littleEndian: v)
            }
            func f32() -> Float {
                let bits = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                offset += 4
                return Float(bitPattern: UInt32(littleEndian: bits))
            }

            // Magic.
            guard raw[0] == 0x46, raw[1] == 0x53, raw[2] == 0x54, raw[3] == 0x52 else {
                return fallback
            }
            offset = 4
            let count = Int(u32())
            var out: [Star] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                guard offset + 17 <= raw.count else { break }
                let ra = Double(f32())
                let dec = Double(f32())
                let mag = Double(f32())
                let ci = Double(f32())
                let nameLen = Int(u8())
                var name = ""
                if nameLen > 0, offset + nameLen <= raw.count {
                    let bytes = Array(UnsafeBufferPointer(
                        start: raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self),
                        count: nameLen))
                    name = String(decoding: bytes, as: UTF8.self)
                    offset += nameLen
                }
                let hasName = !name.isEmpty
                out.append(Star(
                    id: hasName ? name : "HYG-\(i)",
                    raDeg: ra, decDeg: dec, magnitude: mag, colorIndex: ci,
                    properName: hasName ? name : nil))
            }
            return out
        }
    }

    /// A tiny hardcoded fallback if the binary is missing — keeps the app usable.
    private static let fallback: [Star] = [
        Star(id: "Sirius", raDeg: 101.287, decDeg: -16.716, magnitude: -1.46, colorIndex: 0.0, properName: "Sirius"),
        Star(id: "Vega", raDeg: 279.234, decDeg: 38.784, magnitude: 0.03, colorIndex: 0.0, properName: "Vega"),
        Star(id: "Polaris", raDeg: 37.955, decDeg: 89.264, magnitude: 1.98, colorIndex: 0.6, properName: "Polaris"),
        Star(id: "Betelgeuse", raDeg: 88.793, decDeg: 7.407, magnitude: 0.50, colorIndex: 1.85, properName: "Betelgeuse"),
    ]
}

/// Constellation stick-figures, as ordered lists of star names. Each adjacent
/// pair is a line segment. Only stars present by proper name are drawn.
enum Constellations {
    struct Figure { let name: String; let path: [String] }

    static let all: [Figure] = [
        Figure(name: "Orion", path: [
            "Betelgeuse", "Bellatrix", "Mintaka", "Alnilam", "Alnitak", "Rigel",
        ]),
        Figure(name: "Big Dipper", path: [
            "Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid",
        ]),
    ]
}
