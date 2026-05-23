import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    // Published UI state
    @Published private(set) var bluetoothAvailability: BluetoothAvailability = .unknown
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var isAway: Bool = false
    @Published private(set) var lastTriggeredLockAt: Date?
    @Published private(set) var lastSeen: Date?
    @Published private(set) var currentRSSI: Int?

    @Published private(set) var trustedDevice: TrustedDevice?
    @Published var settings: AppSettings

    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []

    // Services
    private let scanner = BluetoothDeviceScanner()
    private let proximityMonitor: ProximityMonitor
    private let lockService = LockService()
    private let loginItemService = LoginItemService()
    private let settingsStore = SettingsStore()
    private let trustedDeviceStore = TrustedDeviceStore()

    // Internal
    private var discoveryRefreshTimer: Timer?
    private var devicesById: [UUID: DiscoveredDevice] = [:]
    private var isDiscovering: Bool = false
    private var screenUnlockObserver: NSObjectProtocol?

    init() {
        let initialSettings = SettingsStore().load()
        self.settings = initialSettings
        self.proximityMonitor = ProximityMonitor(settings: initialSettings)

        self.trustedDevice = trustedDeviceStore.load()

        scanner.delegate = self
        proximityMonitor.delegate = self

        observeScreenUnlock()
    }

    deinit {
        if let observer = screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// macOS posts `com.apple.screenIsUnlocked` via the distributed notification
    /// center whenever the login window dismisses. We use that signal to start
    /// a fresh away-detection cycle so the next walkaway can lock again.
    private func observeScreenUnlock() {
        let center = DistributedNotificationCenter.default()
        screenUnlockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isMonitoring else { return }
                Log.app.notice("screenIsUnlocked → rearming proximity monitor")
                self.proximityMonitor.rearm()
                self.isAway = false
                self.currentRSSI = nil
                self.lastSeen = nil
            }
        }
    }

    // MARK: - Settings

    func updateSettings(_ block: (inout AppSettings) -> Void) {
        var copy = settings
        block(&copy)
        settings = copy
        settingsStore.save(copy)
        proximityMonitor.updateSettings(copy)
    }

    func setStartAtLogin(_ enabled: Bool) {
        let success = loginItemService.setEnabled(enabled)
        updateSettings { $0.startAtLogin = success && enabled }
    }

    // MARK: - Trusted device

    func selectTrustedDevice(_ device: DiscoveredDevice) {
        let trusted = TrustedDevice(identifier: device.id.uuidString, name: device.name)
        trustedDeviceStore.save(trusted)
        trustedDevice = trusted
        Log.app.notice("Trusted device selected: \(trusted.name, privacy: .public) (id=\(trusted.identifier, privacy: .public))")
        // If currently monitoring, restart with new target.
        if isMonitoring {
            startMonitoring()
        }
    }

    func clearTrustedDevice() {
        trustedDeviceStore.clear()
        trustedDevice = nil
        if isMonitoring { stopMonitoring() }
    }

    // MARK: - Discovery (for selection UI)

    func startDeviceDiscovery() {
        isDiscovering = true
        devicesById.removeAll()
        discoveredDevices = []
        scanner.startDiscoveryScan()

        // Periodically prune stale devices and publish a sorted list.
        discoveryRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDiscoveryList() }
        }
        RunLoop.main.add(timer, forMode: .common)
        discoveryRefreshTimer = timer
    }

    func stopDeviceDiscovery() {
        isDiscovering = false
        discoveryRefreshTimer?.invalidate()
        discoveryRefreshTimer = nil
        if !isMonitoring {
            scanner.stopScan()
        } else if let trusted = trustedDevice, let id = UUID(uuidString: trusted.identifier) {
            scanner.startMonitoringScan(forIdentifier: id)
        }
    }

    private func refreshDiscoveryList() {
        let cutoff = Date().addingTimeInterval(-15)
        let filtered = devicesById.values.filter { $0.lastSeen >= cutoff }
        discoveredDevices = filtered.sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard let trusted = trustedDevice,
              let id = UUID(uuidString: trusted.identifier) else {
            return
        }
        proximityMonitor.start()
        scanner.startMonitoringScan(forIdentifier: id)
        isMonitoring = true
        updateSettings { $0.monitoringEnabled = true }
        Log.app.notice("Monitoring started (device=\(trusted.name, privacy: .public), threshold=\(self.settings.rssiThreshold) dBm, awayDelay=\(self.settings.awayDelaySeconds)s)")
    }

    func stopMonitoring() {
        proximityMonitor.stop()
        if !isDiscovering {
            scanner.stopScan()
        }
        isMonitoring = false
        isAway = false
        currentRSSI = nil
        updateSettings { $0.monitoringEnabled = false }
        Log.app.notice("Monitoring stopped")
    }

    // MARK: - Manual actions

    func testLock() {
        _ = lockService.lockScreen()
    }
}

extension AppState: BluetoothDeviceScannerDelegate {
    nonisolated func scanner(_ scanner: BluetoothDeviceScanner, didUpdateAvailability availability: BluetoothAvailability) {
        Task { @MainActor in
            self.bluetoothAvailability = availability
            if availability != .ready, self.isMonitoring {
                self.currentRSSI = nil
            }
        }
    }

    nonisolated func scanner(_ scanner: BluetoothDeviceScanner, didDiscover device: DiscoveredDevice) {
        Task { @MainActor in
            self.devicesById[device.id] = device

            if self.isMonitoring,
               let trusted = self.trustedDevice,
               trusted.identifier == device.id.uuidString {
                self.proximityMonitor.ingest(rssi: device.rssi, at: device.lastSeen)
            }
        }
    }
}

extension AppState: ProximityMonitorDelegate {
    nonisolated func proximityMonitor(_ monitor: ProximityMonitor, didUpdateSmoothedRSSI rssi: Int?, lastSeen: Date?) {
        Task { @MainActor in
            self.currentRSSI = rssi
            self.lastSeen = lastSeen
        }
    }

    nonisolated func proximityMonitor(_ monitor: ProximityMonitor, didDecideAway away: Bool) {
        Task { @MainActor in
            self.isAway = away
        }
    }

    nonisolated func proximityMonitorDidTriggerLock(_ monitor: ProximityMonitor) {
        Task { @MainActor in
            self.lastTriggeredLockAt = Date()
            _ = self.lockService.lockScreen()
        }
    }
}
