#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

CONFIGURATION="${CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-1}"
APP_DIR="${PROJECT_DIR}/build/Broccoli.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${PROJECT_DIR}"
ARCH_ARGUMENTS=()
if [[ "${UNIVERSAL}" == "1" ]]; then
  ARCH_ARGUMENTS=(--arch arm64 --arch x86_64)
fi
swift build -c "${CONFIGURATION}" --product Broccoli "${ARCH_ARGUMENTS[@]}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" "${ARCH_ARGUMENTS[@]}" --show-bin-path)"

if [[ "${APP_DIR}" == "${PROJECT_DIR}/build/Broccoli.app" ]]; then
  rm -rf -- "${APP_DIR}"
fi
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_DIR}/Broccoli" "${MACOS_DIR}/Broccoli"
cp "${PROJECT_DIR}/Support/Info.plist" "${CONTENTS_DIR}/Info.plist"
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
IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS="${PROJECT_DIR}/Support/Broccoli.entitlements"
SIGNING_OPTIONS=(--force --deep --options runtime)
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
    --requirements '=designated => identifier "dev.gauravpandey.broccoli"'
  )
fi
codesign "${APP_SIGNING_OPTIONS[@]}" \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${IDENTITY}" "${APP_DIR}"

echo "Built ${APP_DIR}"
