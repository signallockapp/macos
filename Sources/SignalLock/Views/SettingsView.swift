import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Enable monitoring", isOn: Binding(
                    get: { appState.isMonitoring },
                    set: { newValue in
                        if newValue { appState.startMonitoring() }
                        else { appState.stopMonitoring() }
                    }
                ))
                .disabled(appState.trustedDevice == nil)

                if appState.trustedDevice == nil {
                    Text("Select a trusted device first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sensitivity") {
                HStack {
                    Text("RSSI threshold")
                    Spacer()
                    Text("\(appState.settings.rssiThreshold) dBm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(appState.settings.rssiThreshold) },
                        set: { v in appState.updateSettings { $0.rssiThreshold = Int(v) } }
                    ),
                    in: -100...(-40),
                    step: 1
                )
                Text("Signals weaker than this are treated as 'far'. -80 dBm is a safe default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Away delay") {
                Stepper(
                    "Lock after \(appState.settings.awayDelaySeconds) s of being away",
                    value: Binding(
                        get: { appState.settings.awayDelaySeconds },
                        set: { v in appState.updateSettings { $0.awayDelaySeconds = max(5, v) } }
                    ),
                    in: 5...120,
                    step: 5
                )
                Text("Higher values reduce false locks from BLE noise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Smoothing") {
                Stepper(
                    "Average over last \(appState.settings.rssiSmoothingWindow) samples",
                    value: Binding(
                        get: { appState.settings.rssiSmoothingWindow },
                        set: { v in appState.updateSettings { $0.rssiSmoothingWindow = max(1, v) } }
                    ),
                    in: 1...20
                )
            }

            Section("Startup") {
                Toggle("Start at login", isOn: Binding(
                    get: { appState.settings.startAtLogin },
                    set: { appState.setStartAtLogin($0) }
                ))
            }

            Section("Trusted device") {
                if let device = appState.trustedDevice {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name).font(.headline)
                            Text(device.identifier)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Forget", role: .destructive) {
                            appState.clearTrustedDevice()
                        }
                    }
                } else {
                    Text("No device selected.").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
        .navigationTitle("SignalLock Settings")
    }
}
