import SwiftUI

/// Connect + monitor a Celestron mount. Join the mount's WiFi network
/// (Celestron-XXXX / SkyPortal_XXXX) in iOS Settings first, then connect here.
struct TelescopeSheet: View {
    @ObservedObject var telescope: TelescopeEngine
    @Environment(\.dismiss) private var dismiss
    @State private var host = NexStarClient.defaultHost

    var body: some View {
        NavigationStack {
            Form {
                Section("Celestron mount") {
                    HStack {
                        Circle()
                            .fill(telescope.isConnected ? .green : .secondary)
                            .frame(width: 10, height: 10)
                        Text(telescope.statusText)
                    }
                    if telescope.isConnected {
                        LabeledContent("Aligned", value: telescope.aligned ? "Yes" : "No")
                        LabeledContent("Slewing", value: telescope.slewing ? "Yes" : "No")
                        if let p = telescope.mountRADec {
                            LabeledContent("RA",
                                value: String(format: "%.3f°", p.raDeg))
                            LabeledContent("Dec",
                                value: String(format: "%.3f°", p.decDeg))
                        }
                    }
                }

                Section("Connection") {
                    TextField("Module IP", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    if telescope.isConnected {
                        Button("Disconnect", role: .destructive) { telescope.disconnect() }
                        Button("Stop slew", role: .destructive) { telescope.stop() }
                    } else {
                        Button("Connect") { telescope.connect(host: host) }
                    }
                }

                Section {
                    Text("Join your mount's WiFi (a network named Celestron-XXXX or SkyPortal_XXXX) in Settings, then connect. Once aligned, tap any object in the sky and choose “Point telescope here.”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Telescope")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
