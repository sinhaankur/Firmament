import SwiftUI

/// Settings + about. Display toggles, the data provenance, and the honest
/// "all-custom, on-device, open-source" statement — in keeping with the
/// project's fidelity and privacy principles.
///
/// © Ankur Sinha.
struct SettingsSheet: View {
    @Binding var showConstellations: Bool
    @Binding var nightVision: Bool
    @Environment(\.dismiss) private var dismiss

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    var body: some View {
        NavigationStack {
            Form {
                Section("Sky") {
                    Toggle("Constellation lines", isOn: $showConstellations)
                    Toggle("Night-vision (red)", isOn: $nightVision)
                }

                Section("Data") {
                    row("Positions", "Meeus / JPL ephemeris")
                    row("Stars", "Yale Bright Star Catalogue")
                    row("Satellites", "SGP4 from bundled TLE")
                    row("Weather", "Open-Meteo (keyless)")
                }

                Section("Privacy") {
                    Text("Everything runs on your device. No account, no analytics. Your location and photos never leave the phone; the only network call is an optional weather lookup that sends nothing but a coarse lat/lon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    row("Version", appVersion)
                    row("Code", "100% custom Swift · no third-party libraries")
                    Link(destination: URL(string: "https://github.com/sinhaankur/Firmament")!) {
                        HStack {
                            Text("Open source")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Firmament is the field companion to the web Universe Engine. © Ankur Sinha. Celestron/NexStar/SkyPortal are trademarks of their owners; Firmament is independent and unaffiliated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
