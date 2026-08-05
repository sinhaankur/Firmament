import Foundation
import Combine
import CoreLocation

/// Binds the live sensors to the sky engine and produces, at ~10 Hz, the set of
/// objects currently in the sky with their screen positions filled in on demand.
///
/// It owns the two sensor services and re-resolves the sky as location/time
/// change. Screen projection happens per-frame in the view (it depends on the
/// live pointing direction), so this model just keeps the *sky* current.
@MainActor
final class SkyViewModel: ObservableObject {
    @Published private(set) var objects: [SkyObject] = []
    @Published var date: Date = Date()
    @Published var usingSimulatedLocation = false

    /// All tracked satellites currently above the horizon, as sky labels.
    @Published private(set) var satellites: [SkyObject] = []
    /// The closest satellite up right now (for Spot's "look here").
    @Published private(set) var closestSatellite: SatelliteTracker.Fix?
    /// Soonest upcoming visible pass across the tracked satellites.
    @Published private(set) var nextPass: SatelliteTracker.Pass?

    /// The full naked-eye star field as (alt, az, magnitude) for the point
    /// layer. Recomputed at a low rate (stars move slowly); rendered as dots by
    /// the overlay's Canvas so ~8,900 stars stay cheap.
    @Published private(set) var starField: [(alt: Double, az: Double, mag: Double)] = []
    private var lastStarFieldAt = Date.distantPast

    let location = LocationService()
    let motion = MotionService()
    private let satTracker = SatelliteTracker()
    private var lastPassScan = Date.distantPast

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    /// Fallback observer if the user hasn't granted location yet (Greenwich).
    private let fallback = NightSkyEngine.Observer(latitude: 51.4779, longitude: 0.0)

    func start() {
        location.start()
        motion.start()

        // Recompute the sky a few times a second (objects move slowly, but the
        // clock ticking + first location fix should refresh promptly).
        timer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.recompute() }

        location.$coordinate
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        recompute()
    }

    func stop() {
        timer?.cancel()
        location.stop()
        motion.stop()
    }

    private func recompute() {
        let observer: NightSkyEngine.Observer
        if let c = location.coordinate {
            observer = .init(latitude: c.latitude, longitude: c.longitude)
            usingSimulatedLocation = false
        } else {
            observer = fallback
            usingSimulatedLocation = true
        }
        let engine = NightSkyEngine(observer: observer)
        var all = engine.allObjects(at: date, aboveHorizonOnly: false)
        recomputeSatellites(observer: observer)
        all.append(contentsOf: satellites)   // show satellites as labels too
        objects = all
        recomputeStarField(engine: engine)
    }

    /// Refresh the full point-field ~every 2s (stars barely move at this scale).
    private func recomputeStarField(engine: NightSkyEngine) {
        guard Date().timeIntervalSince(lastStarFieldAt) > 2 else { return }
        lastStarFieldAt = Date()
        starField = engine.stars(at: date, full: true).map {
            (alt: $0.altitude, az: $0.azimuth, mag: $0.magnitude ?? 6)
        }
    }

    /// Resolve all tracked satellites' look angles for the overlay + Spot mode.
    private func recomputeSatellites(observer: NightSkyEngine.Observer) {
        let fixes = satTracker.allFixes(
            latitude: observer.latitude, longitude: observer.longitude, at: date)

        satellites = fixes.filter { $0.altitude > -3 }.map { f in
            SkyObject(
                id: "sat.\(f.name)", name: f.name, kind: .satellite,
                raDeg: 0, decDeg: 0,
                altitude: f.altitude, azimuth: f.azimuth,
                magnitude: -3.0,
                distanceText: String(format: "%.0f km away", f.rangeKm),
                blurb: "\(f.name) — tracked from a stored orbit."
            )
        }

        closestSatellite = fixes.filter { $0.isUp }.min { $0.rangeKm < $1.rangeKm }

        // Refresh the next-pass scan every ~60s (it's a 24h forward scan).
        if nextPass == nil || (nextPass?.start ?? date) < date
            || Date().timeIntervalSince(lastPassScan) > 60 {
            lastPassScan = Date()
            nextPass = satTracker.nextPass(
                latitude: observer.latitude, longitude: observer.longitude, from: date)
        }
    }

    /// Current pointing for the projection, straight from motion.
    var pointing: SkyProjection.Pointing {
        .init(azimuth: motion.pointingAzimuth,
              altitude: motion.pointingAltitude,
              roll: motion.rollDegrees)
    }

    /// The object closest to where the phone is currently pointing (within a
    /// small angular radius), for the Explore reticle's "what am I looking at".
    func nearestToAim(withinDegrees radius: Double = 8) -> SkyObject? {
        let aimAz = motion.pointingAzimuth
        let aimAlt = motion.pointingAltitude
        var best: SkyObject?
        var bestSep = radius
        for obj in objects where obj.altitude > -2 {
            var dAz = obj.azimuth - aimAz
            while dAz > 180 { dAz -= 360 }
            while dAz < -180 { dAz += 360 }
            let dAlt = obj.altitude - aimAlt
            // Cosine-correct the azimuth term so separation is honest near zenith.
            let cosAlt = cos(aimAlt * .pi / 180)
            let sep = (dAz * cosAlt * dAz * cosAlt + dAlt * dAlt).squareRoot()
            if sep < bestSep { bestSep = sep; best = obj }
        }
        return best
    }
}
