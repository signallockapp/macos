import Foundation
import ServiceManagement

final class LoginItemService {
    func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return true }
                try service.register()
            } else {
                if service.status != .enabled { return true }
                try service.unregister()
            }
            return true
        } catch {
            NSLog("[SignalLock] Login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }

    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
