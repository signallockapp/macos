import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []

    private var settingsWindow: NSWindow?
    private var deviceSelectionWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "SignalLock")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        rebuildMenu()
        observeState()
    }

    private func observeState() {
        Publishers.MergeMany(
            appState.$isMonitoring.map { _ in () }.eraseToAnyPublisher(),
            appState.$isAway.map { _ in () }.eraseToAnyPublisher(),
            appState.$lastSeen.map { _ in () }.eraseToAnyPublisher(),
            appState.$currentRSSI.map { _ in () }.eraseToAnyPublisher(),
            appState.$trustedDevice.map { _ in () }.eraseToAnyPublisher(),
            appState.$bluetoothAvailability.map { _ in () }.eraseToAnyPublisher(),
            appState.$lastTriggeredLockAt.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.rebuildMenu() }
        .store(in: &cancellables)

        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDynamicLabels() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func refreshDynamicLabels() {
        // Cheaper than full rebuild — only the "Last Seen" item drifts.
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // Header
        let header = NSMenuItem(title: "SignalLock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Status
        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        // Trusted device
        let trustedTitle: String
        if let d = appState.trustedDevice {
            trustedTitle = "Trusted Device: \(d.name)"
        } else {
            trustedTitle = "Trusted Device: (none)"
        }
        let trusted = NSMenuItem(title: trustedTitle, action: nil, keyEquivalent: "")
        trusted.isEnabled = false
        menu.addItem(trusted)

        // RSSI
        let rssiText: String
        if let rssi = appState.currentRSSI {
            rssiText = "Current Signal: \(rssi) dBm"
        } else {
            rssiText = "Current Signal: —"
        }
        let rssiItem = NSMenuItem(title: rssiText, action: nil, keyEquivalent: "")
        rssiItem.isEnabled = false
        menu.addItem(rssiItem)

        // Last seen
        let lastSeenItem = NSMenuItem(title: "Last Seen: \(lastSeenText())", action: nil, keyEquivalent: "")
        lastSeenItem.isEnabled = false
        menu.addItem(lastSeenItem)

        // Lock trigger info
        if let lockedAt = appState.lastTriggeredLockAt {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .medium
            let item = NSMenuItem(title: "Last Auto-Lock: \(f.string(from: lockedAt))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        // Bluetooth state warnings
        if appState.bluetoothAvailability != .ready {
            let warning = NSMenuItem(title: btWarning(), action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())

        // Start / Pause
        if appState.isMonitoring {
            let item = NSMenuItem(title: "Pause Monitoring", action: #selector(pauseMonitoring), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Start Monitoring", action: #selector(startMonitoring), keyEquivalent: "")
            item.target = self
            item.isEnabled = appState.trustedDevice != nil && appState.bluetoothAvailability == .ready
            menu.addItem(item)
        }

        // Select device
        let select = NSMenuItem(title: "Select Trusted Device…", action: #selector(openDeviceSelection), keyEquivalent: "")
        select.target = self
        menu.addItem(select)

        // Settings
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        // Test lock
        let test = NSMenuItem(title: "Test Lock", action: #selector(testLock), keyEquivalent: "")
        test.target = self
        menu.addItem(test)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SignalLock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine() -> String {
        if appState.isMonitoring {
            return appState.isAway ? "Status: Away (waiting to lock)" : "Status: Monitoring"
        } else {
            return "Status: Paused"
        }
    }

    private func lastSeenText() -> String {
        guard let date = appState.lastSeen else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds) seconds ago" }
        let minutes = seconds / 60
        return "\(minutes) min ago"
    }

    private func btWarning() -> String {
        switch appState.bluetoothAvailability {
        case .poweredOff: return "⚠︎ Bluetooth is off"
        case .unauthorized: return "⚠︎ Bluetooth permission denied"
        case .unsupported: return "⚠︎ BLE not supported on this Mac"
        case .unknown: return "⚠︎ Bluetooth state unknown"
        case .ready: return ""
        }
    }

    // MARK: - Actions

    @objc private func startMonitoring() { appState.startMonitoring() }
    @objc private func pauseMonitoring() { appState.stopMonitoring() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appState: appState)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "SignalLock Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openDeviceSelection() {
        if deviceSelectionWindow == nil {
            let view = DeviceSelectionView(appState: appState) { [weak self] in
                self?.deviceSelectionWindow?.close()
            }
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Select Trusted Device"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            deviceSelectionWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        deviceSelectionWindow?.center()
        deviceSelectionWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func testLock() { appState.testLock() }
    @objc private func quit() { NSApp.terminate(nil) }
}
