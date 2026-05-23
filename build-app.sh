#!/usr/bin/env bash
# Build SignalLock and package as a .app bundle.
# Usage: ./build-app.sh [release|debug]

set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="SignalLock"
BUNDLE_ID="com.signallock.app"
BUILD_DIR=".build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

cd "$(dirname "$0")"

echo "==> Building SignalLock (${CONFIG})"
if [[ "${CONFIG}" == "release" ]]; then
    swift build -c release
    BIN_PATH=".build/release/${APP_NAME}"
else
    swift build
    BIN_PATH=".build/debug/${APP_NAME}"
fi

if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Build failed: binary not found at ${BIN_PATH}"
    exit 1
fi

echo "==> Assembling .app bundle at ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

echo "==> Ad-hoc codesigning (required for Bluetooth permission prompt)"
codesign --force --sign - --deep "${APP_DIR}"

echo "==> Done. Run with: open ${APP_DIR}"
