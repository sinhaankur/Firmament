import Foundation
import AVFoundation

/// What *this specific* camera can actually do for the night sky — discovered at
/// runtime, never assumed. Research across iPhone and Android showed there is no
/// static per-model table: exposure and ISO ceilings live per capture *format*
/// and vary wildly (and Android devices often under-report). NightSky therefore
/// interrogates the hardware and presents its honest limits.
///
/// See `docs/CAMERA-PROFILES.md` for the underlying findings.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
struct DeviceCaptureProfile {
    let modelName: String
    /// Longest single exposure the active format honestly allows (seconds).
    let maxExposureSeconds: Double
    /// Shortest exposure (seconds).
    let minExposureSeconds: Double
    /// ISO ceiling / floor for the active format.
    let maxISO: Float
    let minISO: Float
    /// Apple ProRAW available on this sensor.
    let proRAWAvailable: Bool
    /// Largest still resolution (megapixels) the active format can produce.
    let maxMegapixels: Double
    /// Horizontal field of view of the active format (degrees).
    let horizontalFovDegrees: Double

    /// Whether a hard single-exposure cap means we should rely on stacking.
    /// (On Android/Samsung this cap can be ~0.1 s; stacking is the only answer.)
    var singleExposureIsLimited: Bool { maxExposureSeconds < 0.5 }

    /// A recommended stack depth given the exposure ceiling — deeper stacks when
    /// each frame is short, so total integrated light stays useful.
    var suggestedStackFrames: Int {
        switch maxExposureSeconds {
        case ..<0.25: return 32
        case ..<1.0:  return 24
        default:      return 12
        }
    }

    /// Build a profile from a live capture device + its active format.
    static func detect(from device: AVCaptureDevice,
                       photoOutput: AVCapturePhotoOutput?) -> DeviceCaptureProfile {
        let fmt = device.activeFormat

        let maxDim: (w: Int, h: Int)
        if #available(iOS 16.0, *),
           let d = fmt.supportedMaxPhotoDimensions.max(by: {
               Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
           }) {
            maxDim = (Int(d.width), Int(d.height))
        } else {
            maxDim = (0, 0)
        }
        let mp = Double(maxDim.w * maxDim.h) / 1_000_000.0

        return DeviceCaptureProfile(
            modelName: device.localizedName,
            maxExposureSeconds: fmt.maxExposureDuration.seconds,
            minExposureSeconds: fmt.minExposureDuration.seconds,
            maxISO: fmt.maxISO,
            minISO: fmt.minISO,
            proRAWAvailable: photoOutput?.isAppleProRAWSupported ?? false,
            maxMegapixels: mp,
            horizontalFovDegrees: Double(fmt.videoFieldOfView)
        )
    }

    /// A short human-readable summary for the capture UI.
    var summary: String {
        let exp = maxExposureSeconds >= 1
            ? String(format: "%.0fs", maxExposureSeconds)
            : String(format: "%.0fms", maxExposureSeconds * 1000)
        let raw = proRAWAvailable ? " · ProRAW" : ""
        return "\(exp) · ISO \(Int(minISO))–\(Int(maxISO)) · \(Int(maxMegapixels.rounded()))MP\(raw)"
    }
}
