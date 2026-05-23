#!/usr/bin/env bash
# Package SignalLock.app into a distributable .dmg.
#
# Default usage:
#   ./make-dmg.sh                  Build the .app (release) and produce a DMG.
#   ./make-dmg.sh --skip-build     Use whatever .app is already in .build/.
#
# Optional environment variables for signed / notarized builds (paid Apple
# Developer account required):
#
#   APPLE_DEV_ID    "Developer ID Application: Name (TEAMID)"
#                   — when set, the .app is re-signed with hardened runtime
#                     and a secure timestamp before packaging.
#
#   NOTARY_PROFILE  Keychain profile name created via:
#                     xcrun notarytool store-credentials …
#                   — when set, the .dmg is submitted to Apple's notary
#                     service and the ticket is stapled to the file.
#
# Without these variables the produced DMG is ad-hoc signed only. macOS users
# downloading it will need to right-click → Open the first time, OR run:
#   xattr -dr com.apple.quarantine /Applications/SignalLock.app

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SignalLock"
APP_PATH=".build/${APP_NAME}.app"
INFO_PLIST="Resources/Info.plist"

SKIP_BUILD=false
case "${1:-}" in
    --skip-build) SKIP_BUILD=true ;;
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# 1. Build the .app (unless --skip-build)
# ---------------------------------------------------------------------------
if [[ "${SKIP_BUILD}" == "false" ]]; then
    echo "==> Building ${APP_NAME}.app (release)"
    ./build-app.sh release
fi

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Error: ${APP_PATH} not found. Run without --skip-build first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Resolve version from Info.plist (single source of truth)
# ---------------------------------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
DMG_VOLNAME="${APP_NAME}"
DMG_BASENAME="${APP_NAME}-${VERSION}"
OUT_DMG=".build/${DMG_BASENAME}.dmg"

# ---------------------------------------------------------------------------
# 3. Optional: re-sign with a real Developer ID certificate
# ---------------------------------------------------------------------------
if [[ -n "${APPLE_DEV_ID:-}" ]]; then
    echo "==> Re-signing ${APP_NAME}.app with Developer ID"
    codesign --force --options runtime --timestamp \
        --sign "${APPLE_DEV_ID}" --deep "${APP_PATH}"
    codesign --verify --strict --verbose=2 "${APP_PATH}"
else
    echo "==> APPLE_DEV_ID not set; using ad-hoc signature already on the .app."
fi

# ---------------------------------------------------------------------------
# 4. Stage the DMG layout: app + a "drag here" Applications symlink
# ---------------------------------------------------------------------------
STAGING_PARENT="$(mktemp -d)"
STAGING_DIR="${STAGING_PARENT}/dmg-stage"
mkdir -p "${STAGING_DIR}"
trap 'rm -rf "${STAGING_PARENT}"' EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# ---------------------------------------------------------------------------
# 5. Create a compressed read-only DMG with hdiutil
# ---------------------------------------------------------------------------
rm -f "${OUT_DMG}"
echo "==> Creating ${OUT_DMG}"
hdiutil create \
    -volname "${DMG_VOLNAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    -imagekey zlib-level=9 \
    "${OUT_DMG}" >/dev/null

# ---------------------------------------------------------------------------
# 6. Optional: notarize + staple the DMG
# ---------------------------------------------------------------------------
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Submitting DMG to Apple notarization (this can take a few minutes)"
    xcrun notarytool submit "${OUT_DMG}" \
        --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "${OUT_DMG}"
    xcrun stapler validate "${OUT_DMG}"
else
    echo "==> NOTARY_PROFILE not set; skipping notarization."
    echo "    Users will see a Gatekeeper warning on first launch."
fi

# ---------------------------------------------------------------------------
# 7. Report
# ---------------------------------------------------------------------------
SHA256="$(shasum -a 256 "${OUT_DMG}" | awk '{print $1}')"
SIZE="$(ls -lh "${OUT_DMG}" | awk '{print $5}')"

echo
echo "------------------------------------------------------------"
echo "  Output : ${OUT_DMG}"
echo "  Size   : ${SIZE}"
echo "  SHA256 : ${SHA256}"
echo "  Volume : ${DMG_VOLNAME}"
echo "  Version: ${VERSION}"
echo "------------------------------------------------------------"
echo "Users mount the DMG and drag SignalLock to Applications."
