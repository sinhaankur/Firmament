import Foundation
import Network

/// **NexStarClient** — a from-scratch Swift implementation of the Celestron
/// NexStar communication protocol over the SkyPortal WiFi module.
///
/// Celestron computerized mounts (NexStar SE/SLT/Evolution, CPC, Advanced VX,
/// CGX, Astro Fi, …) expose the documented NexStar serial protocol. The
/// SkyPortal WiFi module bridges it to a TCP socket on the mount's own local
/// network (an SSID like `Celestron-XXXX` / `SkyPortal_XXXX`), default port 2000.
/// This client speaks that protocol directly — get position, GOTO, alignment
/// status, tracking — so NightSky can point the telescope at anything it labels
/// and stamp captures with the mount's exact coordinates.
///
/// © Ankur Sinha. Custom code, no third-party library (protocol per Celestron's
/// public "NexStar Communication Protocol" document).
final class NexStarClient {
    enum ConnectionState: Equatable { case idle, connecting, connected, failed(String) }

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "nightsky.nexstar")
    private(set) var state: ConnectionState = .idle

    /// Default SkyPortal WiFi endpoint once you've joined the mount's network.
    static let defaultHost = "1.2.3.4"   // SkyPortal module gateway; overridable
    static let defaultPort: UInt16 = 2000

    var onStateChange: ((ConnectionState) -> Void)?

    // MARK: - Connect

    func connect(host: String = NexStarClient.defaultHost,
                 port: UInt16 = NexStarClient.defaultPort) {
        setState(.connecting)
        let ep = NWEndpoint.hostPort(
            host: .init(host),
            port: .init(rawValue: port)!
        )
        let conn = NWConnection(to: ep, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready:  self?.setState(.connected)
            case .failed(let e): self?.setState(.failed(e.localizedDescription))
            case .cancelled: self?.setState(.idle)
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        setState(.idle)
    }

    private func setState(_ s: ConnectionState) {
        state = s
        onStateChange?(s)
    }

    // MARK: - Protocol commands

    /// Get the telescope's current pointing as RA/Dec in degrees.
    /// Uses the precise variant ("e"), which returns 32-bit fractions of a turn.
    func getRADec() async -> (raDeg: Double, decDeg: Double)? {
        guard let resp = await send(ascii: "e", expected: 18) else { return nil }
        // Response: "HHHHHHHH,HHHHHHHH#" — two 32-bit hex fractions of 360°.
        let text = String(decoding: resp, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#\n\r"))
        let parts = text.split(separator: ",")
        guard parts.count == 2,
              let ra = UInt32(parts[0], radix: 16),
              let dec = UInt32(parts[1], radix: 16) else { return nil }
        return (fractionToDegrees(ra), signedFractionToDegrees(dec))
    }

    /// Slew (GOTO) to an RA/Dec target in degrees. The mount must be aligned.
    /// Uses the precise GOTO command ("r").
    @discardableResult
    func gotoRADec(raDeg: Double, decDeg: Double) async -> Bool {
        let ra = degreesToFraction(raDeg)
        let dec = degreesToSignedFraction(decDeg)
        let cmd = String(format: "r%08X,%08X", ra, dec)
        // The mount replies with a single '#' on acceptance.
        let resp = await send(ascii: cmd, expected: 1)
        return resp?.first == UInt8(ascii: "#")
    }

    /// Is a GOTO still in progress? ("L" → '0'/'1' + '#')
    func isSlewing() async -> Bool {
        guard let r = await send(ascii: "L", expected: 2) else { return false }
        return r.first == UInt8(ascii: "1")
    }

    /// Is the mount aligned? ("J" → 0/1 byte + '#')
    func isAligned() async -> Bool {
        guard let r = await send(ascii: "J", expected: 2) else { return false }
        return r.first == 1
    }

    /// Stop all motion immediately (cancel GOTO) — "M".
    func stop() async {
        _ = await send(ascii: "M", expected: 1)
    }

    // MARK: - Transport

    /// Send an ASCII command and read up to `expected` bytes of reply.
    private func send(ascii: String, expected: Int) async -> [UInt8]? {
        guard let conn = connection, state == .connected else { return nil }
        return await withCheckedContinuation { cont in
            let data = Data(ascii.utf8)
            conn.send(content: data, completion: .contentProcessed { err in
                if err != nil { cont.resume(returning: nil); return }
                conn.receive(minimumIncompleteLength: 1, maximumLength: expected) { d, _, _, _ in
                    cont.resume(returning: d.map { [UInt8]($0) })
                }
            })
        }
    }

    // MARK: - NexStar fixed-point ↔ degrees

    /// 32-bit unsigned fraction of a full turn → 0…360°.
    private func fractionToDegrees(_ v: UInt32) -> Double {
        Double(v) / 4_294_967_296.0 * 360.0
    }
    /// Signed variant for declination (−180…180°).
    private func signedFractionToDegrees(_ v: UInt32) -> Double {
        var deg = fractionToDegrees(v)
        if deg > 180 { deg -= 360 }
        return deg
    }
    private func degreesToFraction(_ deg: Double) -> UInt32 {
        let norm = deg.truncatingRemainder(dividingBy: 360)
        let positive = norm < 0 ? norm + 360 : norm
        return UInt32((positive / 360.0) * 4_294_967_296.0) & 0xFFFF_FFFF
    }
    private func degreesToSignedFraction(_ deg: Double) -> UInt32 {
        let positive = deg < 0 ? deg + 360 : deg
        return degreesToFraction(positive)
    }
}
