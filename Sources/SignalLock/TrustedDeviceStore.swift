import Foundation

struct TrustedDevice: Codable, Equatable {
    let identifier: String
    let name: String
}

final class TrustedDeviceStore {
    private let defaults: UserDefaults
    private let key = "SignalLock.TrustedDevice.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TrustedDevice? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TrustedDevice.self, from: data)
    }

    func save(_ device: TrustedDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
