import CoreGraphics
import Foundation

/// Projects a celestial object (alt/az) onto the screen given where the phone
/// is currently pointing (from `MotionService`) and the camera's field of view.
///
/// This is a lightweight gnomonic-style projection around the pointing
/// direction — good enough to pin a label near the real object as you sweep the
/// phone. It is intentionally simple; the full AR path (ARKit world tracking +
/// LiDAR occlusion) refines this in Phase 1.
enum SkyProjection {

    struct Pointing {
        let azimuth: Double     // where the camera bore points (deg, 0=N,+E)
        let altitude: Double    // deg above horizon
        let roll: Double        // device roll (deg)
    }

    /// Returns a normalized screen point (0…1 in each axis, origin top-left)
    /// for an object, or nil if it's outside the field of view / behind you.
    /// `hFovDeg` / `vFovDeg` describe the camera's angular coverage.
    static func project(
        objectAz: Double, objectAlt: Double,
        pointing: Pointing,
        hFovDeg: Double, vFovDeg: Double
    ) -> CGPoint? {
        // Angular offset of the object from the pointing direction.
        var dAz = objectAz - pointing.azimuth
        while dAz > 180 { dAz -= 360 }
        while dAz < -180 { dAz += 360 }
        let dAlt = objectAlt - pointing.altitude

        // Reject anything well outside the frame (with a margin so labels can
        // ease in at the edge).
        guard abs(dAz) < hFovDeg * 0.75, abs(dAlt) < vFovDeg * 0.75 else {
            return nil
        }

        // Map angular offset to normalized screen offset from center.
        // Azimuth increases toward East; on screen that's to the right.
        var nx = dAz / hFovDeg
        var ny = -dAlt / vFovDeg     // higher altitude → higher on screen

        // Apply device roll so labels stay level with the horizon.
        let rr = pointing.roll * .pi / 180
        let cosR = cos(rr), sinR = sin(rr)
        let rx = nx * cosR - ny * sinR
        let ry = nx * sinR + ny * cosR
        nx = rx; ny = ry

        return CGPoint(x: 0.5 + nx, y: 0.5 + ny)
    }
}
