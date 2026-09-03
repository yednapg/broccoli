#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-}"
MODE="${2:-rehearse}"
[[ -d "${APP_PATH}" ]] || { print -u2 "usage: scripts/verify-release.sh APP_PATH rehearse|publish"; exit 2; }

INFO="${APP_PATH}/Contents/Info.plist"
EXECUTABLE="${APP_PATH}/Contents/MacOS/Broccoli"
FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"

[[ "$(lipo -archs "${EXECUTABLE}")" == "arm64" ]] || { print -u2 "Release executable is not arm64-only."; exit 1; }
[[ -d "${FRAMEWORK}" ]] || { print -u2 "Sparkle.framework is missing."; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO}")" == "${BROCCOLI_BUNDLE_ID:-dev.gauravpandey.broccoli}" ]] || {
  print -u2 "Bundle identifier does not match the requested identity."
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "${INFO}")" == "true" ]] || { print -u2 "Signed feeds are not required."; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "${INFO}")" == "true" ]] || { print -u2 "Pre-extraction verification is disabled."; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableSystemProfiling' "${INFO}")" == "false" ]] || { print -u2 "System profiling must be disabled."; exit 1; }
if [[ -n "${BROCCOLI_EXPECTED_VERSION:-}" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO}")" == "${BROCCOLI_EXPECTED_VERSION}" ]] || { print -u2 "Marketing version does not match the release request."; exit 1; }
fi
if [[ -n "${BROCCOLI_EXPECTED_BUILD:-}" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO}")" == "${BROCCOLI_EXPECTED_BUILD}" ]] || { print -u2 "Build number does not match the release request."; exit 1; }
fi
codesign --verify --deep --strict "${APP_PATH}"

if [[ "${MODE}" == "publish" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO}")" == "dev.gauravpandey.broccoli" ]] || { print -u2 "Production bundle identifier changed."; exit 1; }
  if codesign -d --entitlements :- "${APP_PATH}" 2>&1 | grep -q 'disable-library-validation'; then
    print -u2 "Production build contains the development library-validation exception."
    exit 1
  fi
  codesign -dvv "${APP_PATH}" 2>&1 | grep -q 'Authority=Developer ID Application' || { print -u2 "Developer ID signature is missing."; exit 1; }
  codesign -dvv "${APP_PATH}" 2>&1 | grep -q 'flags=.*runtime' || { print -u2 "Hardened runtime is missing."; exit 1; }
  codesign -dvv "${APP_PATH}" 2>&1 | grep -q '^Timestamp=' || { print -u2 "Secure signing timestamp is missing."; exit 1; }
  xcrun stapler validate "${APP_PATH}"
  spctl --assess --type execute --verbose=2 "${APP_PATH}"
fi
