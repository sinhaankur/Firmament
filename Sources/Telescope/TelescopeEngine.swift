import Foundation
import Combine

/// **TelescopeEngine** — bridges the `NightSkyEngine`'s catalog to a physical
/// Celestron mount via `NexStarClient`. Tap a star or planet NightSky has
/// identified, and this slews the telescope to it; read back the mount's true
/// pointing to keep the AR overlay honest; and stamp captures with the exact
/// coordinates the scope was on.
///
/// It is opt-in and inert until the user connects — the app is fully usable
/// without a telescope. Nothing here moves the mount without an explicit tap.
///
/// © Ankur Sinha. Custom code, no third-party dependencies.
@MainActor
final class TelescopeEngine: ObservableObject {
    @Published var isConnected = false
    @Published var statusText = "No telescope"
    @Published var aligned = false
    @Published var slewing = false
    /// The mount's last-read pointing (RA/Dec, degrees), if connected.
    @Published var mountRADec: (raDeg: Double, decDeg: Double)?

    private let client = NexStarClient()
    private var poll: Task<Void, Never>?

    init() {
        client.onStateChange = { [weak self] st in
            Task { @MainActor in self?.apply(st) }
        }
    }

    /// Join the mount's WiFi first (Celestron-XXXX / SkyPortal_XXXX), then call
    /// this. Host defaults to the SkyPortal module's gateway.
    func connect(host: String = NexStarClient.defaultHost) {
        statusText = "Connecting…"
        client.connect(host: host)
    }

    func disconnect() {
        poll?.cancel()
        client.disconnect()
    }

    /// Slew the telescope to a NightSky object (uses its J2000 RA/Dec).
    func goto(_ object: SkyObject) {
        guard isConnected else { return }
        statusText = "Slewing to \(object.name)…"
        Task {
            let ok = await client.gotoRADec(raDeg: object.raDeg, decDeg: object.decDeg)
            await MainActor.run {
                statusText = ok ? "Slewing to \(object.name)…" : "GOTO refused (aligned?)"
            }
        }
    }

    func stop() { Task { await client.stop() } }

    private func apply(_ st: NexStarClient.ConnectionState) {
        switch st {
        case .connected:
            isConnected = true
            statusText = "Telescope connected"
            startPolling()
        case .connecting:
            statusText = "Connecting…"
        case .failed(let m):
            isConnected = false
            statusText = "Connect failed: \(m)"
        case .idle:
            isConnected = false
            statusText = "No telescope"
            poll?.cancel()
        }
    }

    /// Poll the mount for position + slew/align status a couple times a second.
    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let radec = await self.client.getRADec()
                let slew = await self.client.isSlewing()
                let alg = await self.client.isAligned()
                await MainActor.run {
                    self.mountRADec = radec
                    self.slewing = slew
                    self.aligned = alg
                    if !slew, self.statusText.hasPrefix("Slewing") {
                        self.statusText = "On target"
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
