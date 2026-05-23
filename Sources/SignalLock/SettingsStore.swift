import Foundation

struct AppSettings: Codable, Equatable {
    var rssiThreshold: Int
    var awayDelaySeconds: Int
    var monitoringEnabled: Bool
    var startAtLogin: Bool
    var rssiSmoothingWindow: Int

    static let `default` = AppSettings(
        rssiThreshold: -80,
        awayDelaySeconds: 20,
        monitoringEnabled: false,
        startAtLogin: false,
        rssiSmoothingWindow: 5
    )
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "SignalLock.Settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
