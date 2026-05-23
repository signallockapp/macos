import Foundation

protocol ProximityMonitorDelegate: AnyObject {
    func proximityMonitor(_ monitor: ProximityMonitor, didUpdateSmoothedRSSI rssi: Int?, lastSeen: Date?)
    func proximityMonitor(_ monitor: ProximityMonitor, didDecideAway away: Bool)
    func proximityMonitorDidTriggerLock(_ monitor: ProximityMonitor)
}

final class ProximityMonitor {
    weak var delegate: ProximityMonitorDelegate?

    private(set) var settings: AppSettings
    private(set) var lastSeen: Date?
    private var rssiBuffer: [Int] = []
    private var awaySince: Date?
    private(set) var isAway: Bool = false
    private(set) var hasTriggeredLockForCurrentAway: Bool = false
    /// One-way gate: `true` only after the trusted device has been observed
    /// near (smoothed RSSI ≥ threshold) since the last `start`/`rearm`.
    /// Prevents a re-lock loop when the user unlocks while the device is
    /// still out of range.
    private var hasConfirmedPresenceSinceArming: Bool = false

    private var evaluationTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        // Trim moving average buffer if window shrank.
        if rssiBuffer.count > settings.rssiSmoothingWindow {
            rssiBuffer.removeFirst(rssiBuffer.count - settings.rssiSmoothingWindow)
        }
    }

    func start() {
        stop()
        rssiBuffer.removeAll()
        lastSeen = nil
        awaySince = nil
        isAway = false
        hasTriggeredLockForCurrentAway = false
        hasConfirmedPresenceSinceArming = false

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer
    }

    func stop() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    /// Reset away-detection state without stopping the evaluation timer.
    /// Called when the user unlocks the Mac so the next walkaway re-arms.
    func rearm() {
        rssiBuffer.removeAll()
        lastSeen = nil
        awaySince = nil
        let wasAway = isAway
        isAway = false
        hasTriggeredLockForCurrentAway = false
        hasConfirmedPresenceSinceArming = false
        delegate?.proximityMonitor(self, didUpdateSmoothedRSSI: nil, lastSeen: nil)
        if wasAway {
            delegate?.proximityMonitor(self, didDecideAway: false)
        }
    }

    func ingest(rssi: Int, at date: Date = Date()) {
        lastSeen = date
        rssiBuffer.append(rssi)
        let window = max(1, settings.rssiSmoothingWindow)
        if rssiBuffer.count > window {
            rssiBuffer.removeFirst(rssiBuffer.count - window)
        }
        let smoothed = smoothedRSSI()
        if !hasConfirmedPresenceSinceArming,
           let smoothed,
           smoothed >= settings.rssiThreshold {
            hasConfirmedPresenceSinceArming = true
            Log.proximity.notice("Presence confirmed (smoothed=\(smoothed) dBm)")
        }
        delegate?.proximityMonitor(self, didUpdateSmoothedRSSI: smoothed, lastSeen: lastSeen)
    }

    func smoothedRSSI() -> Int? {
        guard !rssiBuffer.isEmpty else { return nil }
        let sum = rssiBuffer.reduce(0, +)
        return sum / rssiBuffer.count
    }

    private func evaluate() {
        let now = Date()

        // BLE advertising intervals are sub-second; if no packet has arrived
        // in 3s the smoothed RSSI is stale and would falsely keep
        // `awayBySignal` from firing on sudden disconnects.
        if let last = lastSeen, now.timeIntervalSince(last) > 3.0 {
            rssiBuffer.removeAll()
        }

        // Loop guard: do not evaluate "away" until the device has been
        // confirmed near since arming. Stops re-locking after an unlock when
        // the device is still out of range.
        guard hasConfirmedPresenceSinceArming else { return }

        let awayBySignal: Bool
        let awayBySilence: Bool

        if let smoothed = smoothedRSSI() {
            awayBySignal = smoothed < settings.rssiThreshold
        } else {
            awayBySignal = false
        }

        if let last = lastSeen {
            awayBySilence = now.timeIntervalSince(last) > Double(settings.awayDelaySeconds)
        } else {
            awayBySilence = false
        }

        let away = awayBySignal || awayBySilence

        if away {
            if awaySince == nil {
                // Anchor silence-based away to lastSeen so `elapsed` reflects
                // true absence duration — otherwise the awayDelay is paid
                // twice on sudden disconnects.
                if awayBySilence, let last = lastSeen {
                    awaySince = last
                } else {
                    awaySince = now
                }
                Log.proximity.info("Away condition started (signal=\(awayBySignal), silence=\(awayBySilence))")
            }
            let elapsed = now.timeIntervalSince(awaySince ?? now)
            if elapsed >= Double(settings.awayDelaySeconds) {
                if !isAway {
                    isAway = true
                    Log.proximity.notice("Confirmed AWAY after \(Int(elapsed))s; will trigger lock")
                    delegate?.proximityMonitor(self, didDecideAway: true)
                }
                if !hasTriggeredLockForCurrentAway {
                    hasTriggeredLockForCurrentAway = true
                    delegate?.proximityMonitorDidTriggerLock(self)
                }
            }
        } else {
            if isAway || awaySince != nil {
                Log.proximity.notice("Returned to NEAR; resetting away state")
                isAway = false
                awaySince = nil
                hasTriggeredLockForCurrentAway = false
                delegate?.proximityMonitor(self, didDecideAway: false)
            }
        }
    }
}
