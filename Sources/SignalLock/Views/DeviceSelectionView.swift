import SwiftUI

struct DeviceSelectionView: View {
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select Trusted Device").font(.title3).bold()
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }

            switch appState.bluetoothAvailability {
            case .ready:
                Text("Bring your iPhone or accessory close to the Mac. Pick the device with the strongest signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .poweredOff:
                Text("Bluetooth is turned off. Enable it in Control Center.")
                    .foregroundStyle(.orange)
            case .unauthorized:
                Text("SignalLock does not have Bluetooth permission. Grant access in System Settings → Privacy & Security → Bluetooth.")
                    .foregroundStyle(.orange)
            case .unsupported:
                Text("This Mac does not support Bluetooth Low Energy.")
                    .foregroundStyle(.red)
            case .unknown:
                Text("Initializing Bluetooth…").foregroundStyle(.secondary)
            }

            if appState.discoveredDevices.isEmpty {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                List(appState.discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name).font(.body)
                            Text(device.id.uuidString)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(device.rssi) dBm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Select") {
                            appState.selectTrustedDevice(device)
                            onClose()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(width: 520, height: 460)
        .onAppear { appState.startDeviceDiscovery() }
        .onDisappear { appState.stopDeviceDiscovery() }
    }
}
