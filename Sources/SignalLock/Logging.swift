import Foundation
import os

/// Centralized `os.Logger` instances. All in-app logging goes through here so
/// the user can filter the unified log with a single predicate:
///
///   log stream --predicate 'subsystem == "com.signallock.app"' --info
///
/// All messages should be passed as `.public` interpolations because there is
/// no PII in this app.
enum Log {
    private static let subsystem = "com.signallock.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let lock = Logger(subsystem: subsystem, category: "lock")
    static let proximity = Logger(subsystem: subsystem, category: "proximity")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
}
