#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

cd "${PROJECT_DIR}"

print "==> Running tests"
swift test

print "==> Running performance gates"
zsh "${SCRIPT_DIR}/run-benchmark.sh"

print "==> Building arm64 application"
zsh "${SCRIPT_DIR}/build-app.sh"

APP_PATH="${PROJECT_DIR}/build/Broccoli.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/Broccoli"
ASSET_CATALOG_PATH="${APP_PATH}/Contents/Resources/Assets.car"

print "==> Verifying application signature"
codesign --verify --deep --strict "${APP_PATH}"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "${APP_PATH}/Contents/Info.plist")" != "Broccoli" ]]; then
  print -u2 "Expected CFBundleIconName to reference the adaptive Broccoli icon."
  exit 1
fi
if [[ ! -f "${ASSET_CATALOG_PATH}" ]]; then
  print -u2 "Expected the application bundle to contain an adaptive icon asset catalog."
  exit 1
fi
ASSET_CATALOG_INFO="$(xcrun assetutil --info "${ASSET_CATALOG_PATH}")"
if [[ "${ASSET_CATALOG_INFO}" != *'"Appearance" : "NSAppearanceNameAqua"'* \
      || "${ASSET_CATALOG_INFO}" != *'"Appearance" : "NSAppearanceNameDarkAqua"'* ]]; then
  print -u2 "Expected the Broccoli asset catalog to contain Light and Dark icon renditions."
  exit 1
fi

BUILT_ARCHITECTURES="$(lipo -archs "${EXECUTABLE_PATH}")"
if [[ "${BUILT_ARCHITECTURES}" != "arm64" ]]; then
  print -u2 "Expected an arm64-only executable, found: ${BUILT_ARCHITECTURES}"
  exit 1
fi
if [[ ! -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework" ]]; then
  print -u2 "Expected Sparkle.framework to be embedded."
  exit 1
fi

print "Verification passed (${BUILT_ARCHITECTURES})."
