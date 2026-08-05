//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import Foundation
import CoreLocation
import Combine

/// Publishes the observer's coordinate and true heading. Everything the sky
/// engine needs about *where* and *which way* comes from here.
///
/// Heading uses `trueHeading` (magnetic corrected to geographic north) so
/// azimuths line up with the ephemeris, which is defined against true north.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var trueHeadingDegrees: Double = 0
    @Published var headingAccuracy: Double = -1      // <0 means invalid
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 1  // degrees
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// True when the compass is confident enough to trust the AR overlay.
    var headingIsReliable: Bool {
        headingAccuracy >= 0 && headingAccuracy < 20
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.coordinate = loc.coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.trueHeadingDegrees = newHeading.trueHeading >= 0
                ? newHeading.trueHeading
                : newHeading.magneticHeading
            self.headingAccuracy = newHeading.headingAccuracy
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
