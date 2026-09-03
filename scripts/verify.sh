#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

VERIFY_UNIVERSAL="${VERIFY_UNIVERSAL:-0}"
if [[ "${VERIFY_UNIVERSAL}" != "0" && "${VERIFY_UNIVERSAL}" != "1" ]]; then
  print -u2 "VERIFY_UNIVERSAL must be 0 or 1."
  exit 2
fi

cd "${PROJECT_DIR}"

print "==> Running tests"
swift test

print "==> Running performance gates"
zsh "${SCRIPT_DIR}/run-benchmark.sh"

print "==> Building application (UNIVERSAL=${VERIFY_UNIVERSAL})"
UNIVERSAL="${VERIFY_UNIVERSAL}" zsh "${SCRIPT_DIR}/build-app.sh"

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
if [[ "${VERIFY_UNIVERSAL}" == "1" ]]; then
  if [[ "${BUILT_ARCHITECTURES}" != *arm64* || "${BUILT_ARCHITECTURES}" != *x86_64* ]]; then
    print -u2 "Expected arm64 and x86_64, found: ${BUILT_ARCHITECTURES}"
    exit 1
  fi
fi

print "Verification passed (${BUILT_ARCHITECTURES})."
