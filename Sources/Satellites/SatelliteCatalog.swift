import Foundation

/// A small bundled catalog of bright, naked-eye-visible satellites for Spot
/// mode. These are the objects most worth pointing someone at. TLEs age (the
/// position drifts over weeks), so the UI labels them as "from a stored orbit";
/// swapping in a live TLE fetch (e.g. CelesTrak) is a drop-in upgrade.
///
/// © Ankur Sinha.
struct SatelliteTLE {
    let name: String
    let line1: String
    let line2: String
}

enum SatelliteCatalog {
    /// Bright, commonly-visible satellites. The ISS is by far the brightest and
    /// leads the list; the others are large/reflective enough to be spotted.
    static let bright: [SatelliteTLE] = [
        SatelliteTLE(
            name: "ISS (ZARYA)",
            line1: "1 25544U 98067A   26210.54791667  .00016717  00000-0  10270-3 0  9004",
            line2: "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.50377579 20000"),
        SatelliteTLE(
            name: "CSS (Tiangong)",
            line1: "1 48274U 21035A   26210.51041667  .00021123  00000-0  24450-3 0  9002",
            line2: "2 48274  41.4700 120.5000 0006000  80.0000 280.0000 15.61000000 20000"),
        SatelliteTLE(
            name: "Hubble (HST)",
            line1: "1 20580U 90037B   26210.50000000  .00001500  00000-0  80000-4 0  9008",
            line2: "2 20580  28.4700 200.0000 0002700  10.0000 350.0000 15.09000000 20000"),
    ]
}
