# SignalLock — macOS Menubar App

Native macOS menu-bar utility that automatically locks your Mac when a trusted Bluetooth device (e.g. your iPhone) moves out of range.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode command-line tools (`xcode-select --install`)
- Swift 5.9+

## Build

The app is a Swift Package Manager executable. For the full menu-bar experience (with Bluetooth permission prompt), build it as a `.app` bundle:

```bash
cd macos
./build-app.sh                   # release build
./build-app.sh debug             # debug build
open .build/SignalLock.app       # launch
```

For quick iteration without a bundle (Bluetooth permission may not be granted properly):

```bash
swift run
```

## Required Permissions

On first launch, macOS asks for **Bluetooth** access. Approve it in:

> System Settings → Privacy & Security → Bluetooth

If denied, the menu shows `⚠︎ Bluetooth permission denied`. Re-enable it from the same panel.

The app does **not** require Accessibility, Full Disk Access, Location Services, or any cloud account.

## How Proximity Detection Works

1. You select a **Trusted Device** from a Bluetooth scan. Its identifier is stored locally in `UserDefaults`.
2. While monitoring, `BluetoothDeviceScanner` performs a continuous BLE scan with duplicates allowed and reports advertisement RSSI for the trusted peripheral.
3. `ProximityMonitor` keeps a moving average of recent RSSI samples (default window: 5).
4. The device is considered **away** when **either**:
   - The smoothed RSSI falls below the configured threshold (default: -80 dBm), **or**
   - No advertisement has been received for longer than the away delay (default: 20 s).
5. The away condition must persist for the **away delay** before a lock fires. This grace period is critical — BLE RSSI is noisy and momentary drops are common.
6. After locking once, SignalLock will not lock again until the device is seen back near the Mac, then leaves again.

Tunable from **Settings…**:

- RSSI threshold (-100…-40 dBm)
- Away delay (5–120 s)
- Smoothing window (1–20 samples)
- Start at login (uses `SMAppService`)

## How Locking Works

`LockService` invokes:

```
/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend
```

This puts the screen into the password-locked state without sleeping the system. All shell-out is encapsulated in `LockService`; no other file in the project calls out to the shell.

A **Test Lock** menu item lets you verify the lock action without setting up a device.

## Architecture

```
main.swift                      — entry point; sets accessory activation policy
AppDelegate.swift               — boots AppState + MenuBarController
AppState.swift                  — @MainActor ObservableObject; orchestrates services
MenuBarController.swift         — NSStatusItem + NSMenu, opens settings/selector windows

BluetoothDeviceScanner.swift    — CoreBluetooth wrapper; emits availability + discoveries
ProximityMonitor.swift          — RSSI smoothing + away decision + lock trigger
TrustedDeviceStore.swift        — persists selected device (UserDefaults)
SettingsStore.swift             — persists AppSettings (UserDefaults)
LockService.swift               — invokes CGSession -suspend
LoginItemService.swift          — SMAppService wrapper for "Start at login"

Views/SettingsView.swift        — SwiftUI settings window
Views/DeviceSelectionView.swift — SwiftUI BLE scanner / picker
```

State flows in one direction: `BluetoothDeviceScanner` → `AppState` → `ProximityMonitor` → `LockService`.

## Distribution (.dmg)

Package the built `.app` into a downloadable `.dmg` with the standard
"drag-to-Applications" UX. **The recommended (release-quality) form** signs
the `.app` with your Developer ID and notarizes the DMG with Apple in one shot:

```bash
cd macos
APPLE_DEV_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="signallock-notary" \
./make-dmg.sh
```

This produces `.build/SignalLock-<version>.dmg` that opens without warnings on
any Mac. Replace `APPLE_DEV_ID` with your own developer identity (run
`security find-identity -v -p codesigning` to see the exact string) and
`NOTARY_PROFILE` with the keychain profile you created via
`xcrun notarytool store-credentials`. See **Proper signing + Apple notarization**
below for the one-time keychain setup.

Faster builds without notarization (development only — produces a DMG that
will trigger Gatekeeper on every fresh download):

```bash
./make-dmg.sh                  # builds .app then ad-hoc-signed DMG
./make-dmg.sh --skip-build     # reuses an existing .app
```

`make-dmg.sh` reads the version from `Resources/Info.plist`, stages a folder
containing `SignalLock.app` plus a symlink named `Applications` pointing to
`/Applications`, then creates a compressed read-only DMG (`UDZO` / `zlib-9`).
The output filename embeds the version (e.g. `SignalLock-0.1.0.dmg`).

The script reports the output path, size, SHA-256, and volume name so you can
publish the checksum alongside the download.

### What end users do

1. Download `SignalLock-X.Y.Z.dmg` from the website.
2. Double-click → a Finder window with `SignalLock.app` and an `Applications` shortcut.
3. Drag `SignalLock.app` onto the `Applications` shortcut.
4. Eject the mounted DMG.
5. Launch SignalLock from the Applications folder (Spotlight or Launchpad).

### Gatekeeper on the first launch (ad-hoc builds only)

This applies **only** to DMGs built **without** `APPLE_DEV_ID` and
`NOTARY_PROFILE`. A signed + notarized DMG (the recommended path above)
opens cleanly on any Mac and you can ignore the rest of this section.

An ad-hoc DMG launches successfully on your build machine but Gatekeeper
warns end users on first launch:

> "SignalLock" can't be opened because Apple cannot check it for malicious software.

Tell users to do **one** of the following the first time:

- **Right-click `SignalLock.app` → Open → Open** in the confirmation dialog. Only required once.
- Or, from Terminal: `xattr -dr com.apple.quarantine /Applications/SignalLock.app`
- Or, after the warning appears: System Settings → Privacy & Security → scroll down → "Open Anyway".

### Proper signing + Apple notarization (one-time keychain setup)

You only do this once per Mac. After that, every release is a single
`make-dmg.sh` invocation with the env vars shown above.

```bash
# Store an Apple-issued app-specific password in the login keychain.
# Generate the password at https://account.apple.com → Sign-In and Security →
# App-Specific Passwords (it is shown only once; copy it immediately).
xcrun notarytool store-credentials "signallock-notary" --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"

# Verify credentials work — should print "No submission history." with no errors:
xcrun notarytool history --keychain-profile signallock-notary
```

When `APPLE_DEV_ID` and `NOTARY_PROFILE` are set, `make-dmg.sh`:

1. Re-signs the `.app` with `--options runtime --timestamp` (hardened runtime + secure timestamp — Apple's notarization requirements).
2. Builds the DMG.
3. Submits the DMG to Apple's notary service via `xcrun notarytool submit … --wait`.
4. Staples the notarization ticket onto the DMG via `xcrun stapler staple` so it works offline.
5. Validates the staple.

Result: a DMG that any macOS user can launch on first try with no warnings.

## Diagnostics

All in-app logging goes through `os.Logger` under the subsystem `com.signallock.app`. To watch live logs while testing:

```bash
# All SignalLock logs (info + above)
log stream --predicate 'subsystem == "com.signallock.app"' --info

# Just lock events
log stream --predicate 'subsystem == "com.signallock.app" AND category == "lock"'

# State transitions only (notice level and above)
log stream --predicate 'subsystem == "com.signallock.app"'
```

Log categories:

- `app` — monitoring start/stop, trusted device selection, screen-unlock rearm
- `lock` — which lock strategy fired (`SACLockScreenImmediate`, `CGSession`, or `pmset`) and why fallbacks were skipped
- `proximity` — away condition started, confirmed away (with elapsed seconds), returned to near
- `bluetooth` — Bluetooth state transitions (powered on/off, unauthorized, etc.)

Unrelated noise you may see and can ignore:

- `kernel: (Sandbox) Sandbox: GamePolicyAgent ... deny(1) file-read-xattr` — macOS Game Mode probing every running binary's xattrs. Benign; goes away with a Developer ID signature.
- `tccd ... kTCCServiceListenEvent` / `kTCCServiceScreenCapture` — automatic TCC privacy checks by WindowServer when the app gains focus. We do not request these permissions; the result is `Auth Right: Unknown (None)`.
- `launchservicesd ... seed is different` — caused by relaunching the `.app` repeatedly during development.

## Current Limitations (MVP)

- **iPhones without an active LE advertiser may be hard to track** because iOS rotates BLE addresses for privacy. AirPods, Apple Watch, and most third-party BLE accessories work well; for an iPhone, an alternative is a Bluetooth keychain tag or fitness band.
- No retry/backoff if Bluetooth is briefly unavailable — the app simply pauses scanning and resumes when state changes to `.poweredOn`.
- No notifications when locking. (Planned.)
- No analytics, no telemetry, no network calls. By design.
- Login-item registration requires a properly bundled `.app` (use `build-app.sh`); it will not work for `swift run`.

## Safe Defaults

- Monitoring **auto-starts on launch** when a trusted device is configured (so users cannot forget to enable it). If no trusted device is selected yet, monitoring stays off until the user picks one. Pause Monitoring is always one click away.
- Default RSSI threshold (-80 dBm) and default away delay (20 s) are deliberately conservative to avoid false locks.
- The first lock will not fire until the device has been seen at least once after monitoring starts.

## License

SignalLock is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License v3.0** as published by the Free Software Foundation. See the [`LICENSE`](./LICENSE) file in this directory for the full text, or <https://www.gnu.org/licenses/gpl-3.0.html>.

SignalLock is distributed in the hope that it will be useful, but **without any warranty**; without even the implied warranty of merchantability or fitness for a particular purpose.

### Notes for forks and downstream builds

- The bundle identifier (`com.signallock.app`), Apple Developer signing identity, and notarization credentials referenced in this README are placeholders. If you build and distribute your own binary, **change the bundle ID and sign with your own Apple Developer ID** — Apple ties the bundle ID to the original Team ID, and using it from a different account will not work.
- This repository contains only the macOS app. The marketing website is maintained separately and is not GPL-licensed.
