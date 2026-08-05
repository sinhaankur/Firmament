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

    let location = LocationService()
    let motion = MotionService()

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
        objects = engine.allObjects(at: date, aboveHorizonOnly: false)
    }

    /// Current pointing for the projection, straight from motion.
    var pointing: SkyProjection.Pointing {
        .init(azimuth: motion.pointingAzimuth,
              altitude: motion.pointingAltitude,
              roll: motion.rollDegrees)
    }
}
