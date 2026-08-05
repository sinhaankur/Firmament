import Foundation
import CoreMotion
import Combine

/// Device attitude + steadiness. Two jobs:
///   1. Where is the phone pointing (for the AR sky overlay)?
///   2. Is the phone steady on a tripod (to unlock Night Capture)?
///
/// Attitude is referenced to true north via `.xTrueNorthZVertical` so the
/// overlay's azimuths agree with the ephemeris.
@MainActor
final class MotionService: ObservableObject {
    /// Direction the back camera is pointing, in sky terms.
    @Published var pointingAzimuth: Double = 0    // 0=N, 90=E
    @Published var pointingAltitude: Double = 0   // degrees above horizon
    @Published var rollDegrees: Double = 0
    /// Steadiness for tripod detection.
    @Published var isSteady: Bool = false
    @Published var recentMotion: Double = 0       // rolling accel magnitude

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var motionSamples: [Double] = []

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical, to: queue
        ) { [weak self] data, _ in
            guard let self, let d = data else { return }
            let (az, alt, roll) = Self.pointing(from: d)
            let accel = sqrt(d.userAcceleration.x * d.userAcceleration.x
                           + d.userAcceleration.y * d.userAcceleration.y
                           + d.userAcceleration.z * d.userAcceleration.z)
            Task { @MainActor in
                self.pointingAzimuth = az
                self.pointingAltitude = alt
                self.rollDegrees = roll
                self.ingestMotion(accel)
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }

    /// Feed a new acceleration magnitude; maintain a short rolling window and
    /// decide steadiness. Tripod = consistently tiny motion.
    private func ingestMotion(_ accel: Double) {
        motionSamples.append(accel)
        if motionSamples.count > 30 { motionSamples.removeFirst() }
        let avg = motionSamples.reduce(0, +) / Double(motionSamples.count)
        recentMotion = avg
        // ~0.02 g of residual is a phone sitting still; hand-held is far more.
        isSteady = motionSamples.count >= 20 && avg < 0.02
    }

    /// Convert device attitude into where the *back camera* points.
    /// The camera looks along the device's -Z axis; we express that vector in
    /// the true-north reference frame and read off azimuth + altitude.
    private static func pointing(from d: CMDeviceMotion)
        -> (azimuth: Double, altitude: Double, roll: Double)
    {
        let r = d.attitude.rotationMatrix
        // Camera bore in device coords is -Z. Rotate into the reference frame.
        // reference_vector = R * device_vector, with device -Z = (0,0,-1).
        let x = -r.m13
        let y = -r.m23
        let z = -r.m33
        // Reference frame: X = true north, Y = west, Z = up.
        let azimuth = atan2(-y, x) * 180 / .pi         // 0 = north, +east
        let altitude = asin(max(-1, min(1, z))) * 180 / .pi
        var az = azimuth
        if az < 0 { az += 360 }
        let roll = d.attitude.roll * 180 / .pi
        return (az, altitude, roll)
    }
}
