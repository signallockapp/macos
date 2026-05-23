import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.appState = state
        self.menuBarController = MenuBarController(appState: state)

        // Auto-start monitoring whenever a trusted device is configured.
        // Forgetting to toggle Start Monitoring after setup silently disabled
        // the entire product, so the launch contract is now: if there is a
        // trusted device, the app is protecting you from the moment it loads.
        // The user can still pause from the menu at any time.
        if state.trustedDevice != nil {
            state.startMonitoring()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopMonitoring()
    }
}
