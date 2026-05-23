import Foundation
import CoreBluetooth

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let lastSeen: Date

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum BluetoothAvailability: Equatable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case ready
}

protocol BluetoothDeviceScannerDelegate: AnyObject {
    func scanner(_ scanner: BluetoothDeviceScanner, didUpdateAvailability availability: BluetoothAvailability)
    func scanner(_ scanner: BluetoothDeviceScanner, didDiscover device: DiscoveredDevice)
}

final class BluetoothDeviceScanner: NSObject {
    weak var delegate: BluetoothDeviceScannerDelegate?

    private var central: CBCentralManager!
    private(set) var availability: BluetoothAvailability = .unknown
    private(set) var isScanning: Bool = false
    private var trackedIdentifier: UUID?

    override init() {
        super.init()
        let queue = DispatchQueue(label: "com.signallock.ble", qos: .utility)
        central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
    }

    func startDiscoveryScan() {
        trackedIdentifier = nil
        startScanIfPossible()
    }

    func startMonitoringScan(forIdentifier identifier: UUID) {
        trackedIdentifier = identifier
        startScanIfPossible()
    }

    func stopScan() {
        if central.isScanning {
            central.stopScan()
        }
        isScanning = false
    }

    private func startScanIfPossible() {
        guard availability == .ready else { return }
        if central.isScanning {
            central.stopScan()
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }
}

extension BluetoothDeviceScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        let new: BluetoothAvailability
        switch manager.state {
        case .unknown, .resetting:
            new = .unknown
        case .unsupported:
            new = .unsupported
        case .unauthorized:
            new = .unauthorized
        case .poweredOff:
            new = .poweredOff
        case .poweredOn:
            new = .ready
        @unknown default:
            new = .unknown
        }
        availability = new
        Log.bluetooth.notice("Availability changed: \(String(describing: new), privacy: .public)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.scanner(self, didUpdateAvailability: new)
        }

        if new == .ready, isScanning == false, trackedIdentifier != nil {
            startScanIfPossible()
        }
    }

    func centralManager(_ manager: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        // CoreBluetooth uses 127 to indicate the RSSI is not available.
        guard rssi != 127 else { return }

        if let tracked = trackedIdentifier, peripheral.identifier != tracked {
            return
        }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unknown Device"

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: rssi,
            lastSeen: Date()
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.scanner(self, didDiscover: device)
        }
    }
}
