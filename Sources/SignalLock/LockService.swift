import Foundation

/// All shell-out and private-API access for locking the screen lives here.
/// No other module is allowed to spawn processes or load private frameworks.
final class LockService {
    enum Strategy: String {
        case privateLoginAPI = "login.framework!SACLockScreenImmediate"
        case cgSession = "CGSession -suspend"
        case pmsetDisplaySleep = "pmset displaysleepnow"
    }

    /// Candidate paths for the private `login` binary. macOS no longer ships
    /// these as on-disk Mach-O files — `dlopen` resolves them via the dyld
    /// shared cache. Existence checks would be misleading, so we just try.
    private let loginFrameworkPaths = [
        "/System/Library/PrivateFrameworks/login.framework/login",
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
    ]

    private let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    private let pmsetPath = "/usr/bin/pmset"

    @discardableResult
    func lockScreen() -> Strategy? {
        if tryPrivateLoginAPI() {
            Log.lock.notice("Locked via SACLockScreenImmediate")
            return .privateLoginAPI
        }
        if tryCGSession() {
            Log.lock.notice("Locked via CGSession -suspend")
            return .cgSession
        }
        if tryPmsetDisplaySleep() {
            Log.lock.notice("Triggered display sleep via pmset (locks only if 'Require password' is on)")
            return .pmsetDisplaySleep
        }
        Log.lock.error("All lock strategies failed")
        return nil
    }

    // MARK: - Strategies

    private func tryPrivateLoginAPI() -> Bool {
        for path in loginFrameworkPaths {
            guard let handle = dlopen(path, RTLD_LAZY) else {
                let err = dlerror().map { String(cString: $0) } ?? "unknown"
                Log.lock.debug("dlopen failed at \(path, privacy: .public): \(err, privacy: .public)")
                continue
            }
            defer { dlclose(handle) }

            guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
                Log.lock.debug("SACLockScreenImmediate not found in \(path, privacy: .public)")
                continue
            }
            typealias LockFn = @convention(c) () -> Int32
            let fn = unsafeBitCast(sym, to: LockFn.self)
            let rc = fn()
            if rc == 0 { return true }
            Log.lock.error("SACLockScreenImmediate returned \(rc) (path \(path, privacy: .public))")
        }
        return false
    }

    private func tryCGSession() -> Bool {
        guard FileManager.default.fileExists(atPath: cgSessionPath) else {
            Log.lock.debug("CGSession binary not present at \(self.cgSessionPath, privacy: .public)")
            return false
        }
        return runProcess(executable: cgSessionPath, arguments: ["-suspend"])
    }

    private func tryPmsetDisplaySleep() -> Bool {
        guard FileManager.default.fileExists(atPath: pmsetPath) else { return false }
        return runProcess(executable: pmsetPath, arguments: ["displaysleepnow"])
    }

    // MARK: - Helpers

    private func runProcess(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return true }
            let errStr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            Log.lock.error("\(executable, privacy: .public) exited \(process.terminationStatus); stderr=\(errStr, privacy: .public)")
            return false
        } catch {
            Log.lock.error("Failed to run \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
