import Foundation

/// A compact bundled catalog of the brightest / most recognizable stars.
///
/// Positions are J2000 right ascension / declination (degrees) and apparent
/// visual magnitude, from the Yale Bright Star Catalogue / Hipparcos. Proper
/// motion is ignored (negligible for naked-eye pointing over decades). This is
/// a starter set for Phase 0 — the full HYG catalog slots in behind the same
/// `Star` type in Phase 1.
struct Star: Identifiable {
    let id: String        // common name
    let raDeg: Double
    let decDeg: Double
    let magnitude: Double
    var name: String { id }
}

enum StarCatalog {
    /// ~40 of the brightest stars, spanning both hemispheres.
    static let bright: [Star] = [
        Star(id: "Sirius",      raDeg: 101.287,  decDeg: -16.716, magnitude: -1.46),
        Star(id: "Canopus",     raDeg: 95.988,   decDeg: -52.696, magnitude: -0.74),
        Star(id: "Rigil Kent.", raDeg: 219.902,  decDeg: -60.834, magnitude: -0.27),
        Star(id: "Arcturus",    raDeg: 213.915,  decDeg: 19.182,  magnitude: -0.05),
        Star(id: "Vega",        raDeg: 279.234,  decDeg: 38.784,  magnitude: 0.03),
        Star(id: "Capella",     raDeg: 79.172,   decDeg: 45.998,  magnitude: 0.08),
        Star(id: "Rigel",       raDeg: 78.634,   decDeg: -8.202,  magnitude: 0.13),
        Star(id: "Procyon",     raDeg: 114.826,  decDeg: 5.225,   magnitude: 0.34),
        Star(id: "Betelgeuse",  raDeg: 88.793,   decDeg: 7.407,   magnitude: 0.50),
        Star(id: "Achernar",    raDeg: 24.429,   decDeg: -57.237, magnitude: 0.46),
        Star(id: "Hadar",       raDeg: 210.956,  decDeg: -60.373, magnitude: 0.61),
        Star(id: "Altair",      raDeg: 297.696,  decDeg: 8.868,   magnitude: 0.76),
        Star(id: "Acrux",       raDeg: 186.650,  decDeg: -63.099, magnitude: 0.77),
        Star(id: "Aldebaran",   raDeg: 68.980,   decDeg: 16.509,  magnitude: 0.85),
        Star(id: "Antares",     raDeg: 247.352,  decDeg: -26.432, magnitude: 1.09),
        Star(id: "Spica",       raDeg: 201.298,  decDeg: -11.161, magnitude: 1.04),
        Star(id: "Pollux",      raDeg: 116.329,  decDeg: 28.026,  magnitude: 1.14),
        Star(id: "Fomalhaut",   raDeg: 344.413,  decDeg: -29.622, magnitude: 1.16),
        Star(id: "Deneb",       raDeg: 310.358,  decDeg: 45.280,  magnitude: 1.25),
        Star(id: "Mimosa",      raDeg: 191.930,  decDeg: -59.689, magnitude: 1.25),
        Star(id: "Regulus",     raDeg: 152.093,  decDeg: 11.967,  magnitude: 1.35),
        Star(id: "Adhara",      raDeg: 104.656,  decDeg: -28.972, magnitude: 1.50),
        Star(id: "Castor",      raDeg: 113.650,  decDeg: 31.888,  magnitude: 1.57),
        Star(id: "Shaula",      raDeg: 263.402,  decDeg: -37.104, magnitude: 1.62),
        Star(id: "Bellatrix",   raDeg: 81.283,   decDeg: 6.350,   magnitude: 1.64),
        Star(id: "Elnath",      raDeg: 81.573,   decDeg: 28.608,  magnitude: 1.65),
        Star(id: "Alnilam",     raDeg: 84.053,   decDeg: -1.202,  magnitude: 1.69),
        Star(id: "Alnitak",     raDeg: 85.190,   decDeg: -1.943,  magnitude: 1.74),
        Star(id: "Alioth",      raDeg: 193.507,  decDeg: 55.960,  magnitude: 1.77),
        Star(id: "Dubhe",       raDeg: 165.932,  decDeg: 61.751,  magnitude: 1.79),
        Star(id: "Mirfak",      raDeg: 51.081,   decDeg: 49.861,  magnitude: 1.79),
        Star(id: "Polaris",     raDeg: 37.955,   decDeg: 89.264,  magnitude: 1.98),
        Star(id: "Alkaid",      raDeg: 206.885,  decDeg: 49.313,  magnitude: 1.85),
        Star(id: "Mintaka",     raDeg: 83.002,   decDeg: -0.299,  magnitude: 2.23),
        Star(id: "Merak",       raDeg: 165.460,  decDeg: 56.383,  magnitude: 2.37),
        Star(id: "Phecda",      raDeg: 178.458,  decDeg: 53.695,  magnitude: 2.44),
        Star(id: "Megrez",      raDeg: 183.857,  decDeg: 57.033,  magnitude: 3.31),
        Star(id: "Mizar",       raDeg: 200.981,  decDeg: 54.925,  magnitude: 2.04),
        Star(id: "Denebola",    raDeg: 177.265,  decDeg: 14.572,  magnitude: 2.11),
        Star(id: "Algol",       raDeg: 47.042,   decDeg: 40.956,  magnitude: 2.12),
    ]

    static func star(named name: String) -> Star? {
        bright.first { $0.id == name }
    }
}

/// Constellation stick-figures, as ordered lists of star names. Each adjacent
/// pair is a line segment. Only stars present in `StarCatalog.bright` are used.
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
