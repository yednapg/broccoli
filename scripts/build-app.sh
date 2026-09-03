#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="${BROCCOLI_APP_DIR:-${PROJECT_DIR}/build/Broccoli.app}"
if [[ "${APP_DIR}" != /*/Broccoli.app ]]; then
  print -u2 "BROCCOLI_APP_DIR must be an absolute path ending in /Broccoli.app."
  exit 2
fi
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
SPARKLE_FRAMEWORK="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

cd "${PROJECT_DIR}"
ARCH_ARGUMENTS=(--arch arm64)
swift build -c "${CONFIGURATION}" --product Broccoli "${ARCH_ARGUMENTS[@]}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" "${ARCH_ARGUMENTS[@]}" --show-bin-path)"

rm -rf -- "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"
cp "${BIN_DIR}/Broccoli" "${MACOS_DIR}/Broccoli"
cp "${PROJECT_DIR}/Support/Info.plist" "${CONTENTS_DIR}/Info.plist"
if [[ ! -d "${SPARKLE_FRAMEWORK}" ]]; then
  print -u2 "Sparkle.framework 2.9.6 was not resolved at the expected SwiftPM artifact path."
  exit 1
fi
ditto "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/Sparkle.framework"
ICON_COMPOSER_DOCUMENT="${PROJECT_DIR}/Support/Broccoli.icon"
if [[ -d "${ICON_COMPOSER_DOCUMENT}" ]] && ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
  ICON_PARTIAL_INFO="${CONTENTS_DIR}/BroccoliIconInfo.plist"
  "${ACTOOL}" "${ICON_COMPOSER_DOCUMENT}" \
    --compile "${RESOURCES_DIR}" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --target-device mac \
    --app-icon Broccoli \
    --output-partial-info-plist "${ICON_PARTIAL_INFO}" \
    --warnings \
    --notices
  if [[ ! -f "${RESOURCES_DIR}/Assets.car" || ! -f "${RESOURCES_DIR}/Broccoli.icns" ]]; then
    print -u2 "Icon Composer did not produce the required adaptive icon resources."
    exit 1
  fi
  rm -f -- "${ICON_PARTIAL_INFO}"
else
  # Keep a legacy light icon only for toolchains that cannot compile Icon Composer documents.
  # The supported full-Xcode build path above is required for adaptive Light/Dark artwork.
  cp "${PROJECT_DIR}/Support/Broccoli.icns" "${RESOURCES_DIR}/Broccoli.icns"
fi
cp "${PROJECT_DIR}/Support/Brand/Broccoli-AppIcon-Light-1024.png" \
  "${RESOURCES_DIR}/Broccoli-AppIcon-Light-1024.png"
cp "${PROJECT_DIR}/Support/Brand/Broccoli-AppIcon-Dark-1024.png" \
  "${RESOURCES_DIR}/Broccoli-AppIcon-Dark-1024.png"

if [[ -n "${BROCCOLI_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BROCCOLI_VERSION}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "${BROCCOLI_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BROCCOLI_BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "${BROCCOLI_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BROCCOLI_BUNDLE_ID}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "${BROCCOLI_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${BROCCOLI_FEED_URL}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "${BROCCOLI_SPARKLE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${BROCCOLI_SPARKLE_PUBLIC_KEY}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ "${BROCCOLI_UPDATE_ENV:-production}" == "local" ]]; then
  LOCAL_BUNDLE_ID="${BROCCOLI_BUNDLE_ID:-dev.gauravpandey.broccoli.updatetest}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${LOCAL_BUNDLE_ID}" "${CONTENTS_DIR}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "${CONTENTS_DIR}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "${CONTENTS_DIR}/Info.plist"
fi
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CONTENTS_DIR}/Info.plist")"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS="${PROJECT_DIR}/Support/Broccoli.entitlements"
SIGNING_OPTIONS=(--force --options runtime)
APP_SIGNING_OPTIONS=(--force --options runtime)
if [[ "${IDENTITY}" == "-" ]]; then
  ENTITLEMENTS="${PROJECT_DIR}/Support/BroccoliDevelopment.entitlements"
  SIGNING_OPTIONS+=(--timestamp=none)
  APP_SIGNING_OPTIONS+=(--timestamp=none)
else
  # Developer ID distributions need Apple's trusted timestamp for notarization and
  # long-term Gatekeeper validation after the signing certificate expires.
  SIGNING_OPTIONS+=(--timestamp)
  APP_SIGNING_OPTIONS+=(--timestamp)
fi
if [[ "${IDENTITY}" == "-" ]]; then
  # Ad-hoc signing normally derives the designated requirement from the
  # executable's CDHash, which changes on every local build. TCC then keeps the
  # old permission row enabled while rejecting the rebuilt app. Give local
  # Broccoli builds a stable app-level requirement so the window-management
  # permission survives rebuilds.
  APP_SIGNING_OPTIONS+=(
    --requirements "=designated => identifier \"${ACTUAL_BUNDLE_ID}\""
  )
fi

if [[ "${BROCCOLI_DISTRIBUTION:-0}" == "1" ]]; then
  if [[ "${IDENTITY}" == "-" ]]; then
    print -u2 "Distribution builds require CODE_SIGN_IDENTITY to be a Developer ID Application identity."
    exit 1
  fi
  if [[ "${BROCCOLI_BUNDLE_ID:-dev.gauravpandey.broccoli}" != "dev.gauravpandey.broccoli" ]]; then
    print -u2 "Distribution builds must use the permanent dev.gauravpandey.broccoli bundle identifier."
    exit 1
  fi
  if [[ -z "${BROCCOLI_SPARKLE_PUBLIC_KEY:-}" || "${BROCCOLI_SPARKLE_PUBLIC_KEY}" == "CONFIGURE_AT_BUILD_TIME" ]]; then
    print -u2 "Distribution builds require BROCCOLI_SPARKLE_PUBLIC_KEY."
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "${ENTITLEMENTS}" >/dev/null 2>&1; then
    print -u2 "Production entitlements must not disable library validation."
    exit 1
  fi
fi

# Sparkle contains independently signed helpers. Sign nested code from the inside out;
# never use --deep because it can conceal a missed or incorrectly entitled component.
SPARKLE_VERSION_DIR="${FRAMEWORKS_DIR}/Sparkle.framework/Versions/B"
for NESTED_COMPONENT in \
  "${SPARKLE_VERSION_DIR}/XPCServices/Downloader.xpc" \
  "${SPARKLE_VERSION_DIR}/XPCServices/Installer.xpc" \
  "${SPARKLE_VERSION_DIR}/Autoupdate" \
  "${SPARKLE_VERSION_DIR}/Updater.app"; do
  codesign "${SIGNING_OPTIONS[@]}" \
    --preserve-metadata=entitlements \
    --sign "${IDENTITY}" "${NESTED_COMPONENT}"
done
codesign "${SIGNING_OPTIONS[@]}" \
  --preserve-metadata=entitlements \
  --sign "${IDENTITY}" "${FRAMEWORKS_DIR}/Sparkle.framework"
codesign "${APP_SIGNING_OPTIONS[@]}" \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${IDENTITY}" "${APP_DIR}"

echo "Built ${APP_DIR}"
