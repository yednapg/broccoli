#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

HARNESS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/broccoli-update-rehearsal.XXXXXX")"
KEYCHAIN_PATH="${HARNESS_ROOT}/SparkleTest.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
KEY_ACCOUNT="dev.gauravpandey.broccoli.rehearsal.$(uuidgen)"
SERVER_ROOT="${HARNESS_ROOT}/server"
ISOLATED_APPLICATIONS="${HARNESS_ROOT}/Applications"
OUTPUT="${SERVER_ROOT}"
HARNESS_APP="${HARNESS_ROOT}/build/Broccoli.app"
PORT="${BROCCOLI_REHEARSAL_PORT:-18765}"
FAULT="${BROCCOLI_REHEARSAL_FAULT:-none}"
SERVER_PID=""
ORIGINAL_DEFAULT_KEYCHAIN="$(security default-keychain -d user | tr -d ' \"')"
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | tr -d ' \"')}")

cleanup() {
  set +e
  [[ -n "${SERVER_PID}" ]] && kill "${SERVER_PID}" >/dev/null 2>&1
  pkill -f "${ISOLATED_APPLICATIONS}/Broccoli.app/Contents/MacOS/Broccoli" >/dev/null 2>&1
  defaults delete dev.gauravpandey.broccoli.updatetest >/dev/null 2>&1
  if [[ "${BROCCOLI_TEST_HOMEBREW:-0}" == "1" ]]; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask broccoli-local-rehearsal >/dev/null 2>&1
    HOMEBREW_NO_AUTO_UPDATE=1 brew untap broccoli/rehearsal >/dev/null 2>&1
  fi
  if [[ -n "${ORIGINAL_DEFAULT_KEYCHAIN}" ]]; then
    security default-keychain -d user -s "${ORIGINAL_DEFAULT_KEYCHAIN}" >/dev/null 2>&1
  fi
  RESTORED_KEYCHAINS=()
  for ORIGINAL_KEYCHAIN in "${ORIGINAL_KEYCHAINS[@]}"; do
    [[ -e "${ORIGINAL_KEYCHAIN}" ]] && RESTORED_KEYCHAINS+=("${ORIGINAL_KEYCHAIN}")
  done
  if (( ${#RESTORED_KEYCHAINS[@]} > 0 )); then
    security list-keychains -d user -s "${RESTORED_KEYCHAINS[@]}" >/dev/null 2>&1
  fi
  security delete-keychain "${KEYCHAIN_PATH}" >/dev/null 2>&1
  if [[ "${HARNESS_ROOT}" == "${TMPDIR:-/tmp}"/broccoli-update-rehearsal.* ]]; then
    rm -rf -- "${HARNESS_ROOT}"
  fi
}
trap cleanup EXIT INT TERM

if [[ "${BROCCOLI_TEST_HOMEBREW_ZAP:-0}" == "1" && "${BROCCOLI_DISPOSABLE_ACCOUNT:-}" != "YES" ]]; then
  print -u2 "Destructive Homebrew zap testing requires BROCCOLI_DISPOSABLE_ACCOUNT=YES in a disposable account or VM."
  exit 1
fi
case "${FAULT}" in
  none|tampered-feed|tampered-archive|truncated-archive|wrong-length|offline) ;;
  *) print -u2 "Unknown BROCCOLI_REHEARSAL_FAULT: ${FAULT}"; exit 2 ;;
esac

mkdir -p "${SERVER_ROOT}" "${ISOLATED_APPLICATIONS}"
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security list-keychains -d user -s "${KEYCHAIN_PATH}" "${ORIGINAL_KEYCHAINS[@]}"
security default-keychain -d user -s "${KEYCHAIN_PATH}"

SPARKLE_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin"
print "==> Creating disposable Sparkle signing key"
PUBLIC_KEY="$(${SPARKLE_BIN}/generate_keys --account "${KEY_ACCOUNT}" | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' | head -1)"
[[ -n "${PUBLIC_KEY}" ]] || { print -u2 "Sparkle did not return a public key."; exit 1; }
PRIVATE_KEY_FILE="${HARNESS_ROOT}/sparkle-private-key"
"${SPARKLE_BIN}/generate_keys" --account "${KEY_ACCOUNT}" -x "${PRIVATE_KEY_FILE}" >/dev/null
chmod 600 "${PRIVATE_KEY_FILE}"

NOTES_PATH="${HARNESS_ROOT}/0.0.2.md"
print -r -- "# Broccoli 0.0.2" > "${NOTES_PATH}"
print -r -- "" >> "${NOTES_PATH}"
print -r -- "Local-only signed update rehearsal." >> "${NOTES_PATH}"

print "==> Building signed-feed update 0.0.2 (2)"
BROCCOLI_SPARKLE_KEY_ACCOUNT="${KEY_ACCOUNT}" \
BROCCOLI_SPARKLE_PUBLIC_KEY="${PUBLIC_KEY}" \
BROCCOLI_SPARKLE_PRIVATE_KEY_FILE="${PRIVATE_KEY_FILE}" \
BROCCOLI_APP_DIR="${HARNESS_APP}" \
BROCCOLI_UPDATE_ENV=local \
BROCCOLI_BUNDLE_ID=dev.gauravpandey.broccoli.updatetest \
BROCCOLI_FEED_URL="http://127.0.0.1:${PORT}/appcast.xml" \
BROCCOLI_DOWNLOAD_URL_PREFIX="http://127.0.0.1:${PORT}" \
  zsh "${SCRIPT_DIR}/release.sh" \
    --mode rehearse \
    --version 0.0.2 \
    --build 2 \
    --channel stable \
    --priority routine \
    --notes "${NOTES_PATH}" \
    --output "${OUTPUT}"

print "==> Building isolated baseline 0.0.1 (1)"
BROCCOLI_VERSION=0.0.1 \
BROCCOLI_BUILD_NUMBER=1 \
BROCCOLI_SPARKLE_PUBLIC_KEY="${PUBLIC_KEY}" \
BROCCOLI_UPDATE_ENV=local \
BROCCOLI_BUNDLE_ID=dev.gauravpandey.broccoli.updatetest \
BROCCOLI_FEED_URL="http://127.0.0.1:${PORT}/appcast.xml" \
BROCCOLI_APP_DIR="${HARNESS_APP}" \
  CODE_SIGN_IDENTITY=- zsh "${SCRIPT_DIR}/build-app.sh"

BASELINE_ARCHIVE="${SERVER_ROOT}/Broccoli-0.0.1.zip"
ditto -c -k --sequesterRsrc --keepParent "${HARNESS_APP}" "${BASELINE_ARCHIVE}"

UPDATE_ARCHIVE="${SERVER_ROOT}/Broccoli-0.0.2.zip"
case "${FAULT}" in
  tampered-feed)
    sed -i '' 's#<broccoli:priority>routine</broccoli:priority>#<broccoli:priority>important</broccoli:priority>#' "${SERVER_ROOT}/appcast.xml"
    ;;
  tampered-archive)
    print -n -- "tampered" >> "${UPDATE_ARCHIVE}"
    ;;
  truncated-archive)
    ARCHIVE_SIZE="$(stat -f %z "${UPDATE_ARCHIVE}")"
    /usr/bin/head -c "$(( ARCHIVE_SIZE / 2 ))" "${UPDATE_ARCHIVE}" > "${UPDATE_ARCHIVE}.truncated"
    mv "${UPDATE_ARCHIVE}.truncated" "${UPDATE_ARCHIVE}"
    ;;
  wrong-length)
    sed -i '' '/<enclosure /s/length="[0-9][0-9]*"/length="1"/' "${SERVER_ROOT}/appcast.xml"
    "${SPARKLE_BIN}/sign_update" --ed-key-file "${PRIVATE_KEY_FILE}" "${SERVER_ROOT}/appcast.xml" >/dev/null
    ;;
esac

if [[ "${FAULT}" != "offline" ]]; then
  python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${SERVER_ROOT}" > "${HARNESS_ROOT}/http.log" 2>&1 &
  SERVER_PID=$!
  for _ in {1..20}; do
    curl --fail --silent "http://127.0.0.1:${PORT}/appcast.xml" >/dev/null 2>&1 && break
    sleep 0.25
  done
  if ! curl --fail --silent --show-error "http://127.0.0.1:${PORT}/appcast.xml" >/dev/null; then
    print -u2 "Local update server failed to become ready on port ${PORT}:"
    sed -n '1,120p' "${HARNESS_ROOT}/http.log" >&2
    exit 1
  fi
fi

if [[ "${BROCCOLI_TEST_HOMEBREW:-0}" == "1" ]]; then
  print "==> Installing baseline through a temporary local Homebrew cask"
  BASELINE_SHA="$(shasum -a 256 "${BASELINE_ARCHIVE}" | awk '{print $1}')"
  HOMEBREW_NO_AUTO_UPDATE=1 brew tap-new broccoli/rehearsal >/dev/null
  TAP_DIR="$(brew --repository broccoli/rehearsal)"
  CASK_DIR="${TAP_DIR}/Casks"
  mkdir -p "${CASK_DIR}"
  "${SCRIPT_DIR}/generate-casks.sh" \
    --version 0.0.1 \
    --sha256 "${BASELINE_SHA}" \
    --url "http://127.0.0.1:${PORT}/Broccoli-0.0.1.zip" \
    --channel stable \
    --output "${CASK_DIR}"
  sed -i '' 's/cask "broccoli"/cask "broccoli-local-rehearsal"/' "${CASK_DIR}/broccoli.rb"
  sed -i '' 's/dev.gauravpandey.broccoli/dev.gauravpandey.broccoli.updatetest/g' "${CASK_DIR}/broccoli.rb"
  mv "${CASK_DIR}/broccoli.rb" "${CASK_DIR}/broccoli-local-rehearsal.rb"
  HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask --appdir="${ISOLATED_APPLICATIONS}" broccoli/rehearsal/broccoli-local-rehearsal
else
  ditto "${HARNESS_APP}" "${ISOLATED_APPLICATIONS}/Broccoli.app"
fi

INSTALLED_APP="${ISOLATED_APPLICATIONS}/Broccoli.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INSTALLED_APP}/Contents/Info.plist")" == "1" ]] || {
  print -u2 "Baseline installation did not contain build 1."
  exit 1
}

if [[ "${BROCCOLI_TEST_HOMEBREW:-0}" == "1" ]]; then
  xattr -p com.apple.quarantine "${INSTALLED_APP}" >/dev/null 2>&1 || {
    print -u2 "Expected Homebrew to quarantine the downloaded rehearsal app."
    exit 1
  }
  # An ad-hoc signature cannot pass Gatekeeper. The production matrix must retain
  # quarantine and use the notarized build; this local harness removes it only after
  # proving Homebrew applied it so the Sparkle replacement path can be exercised.
  xattr -dr com.apple.quarantine "${INSTALLED_APP}"
fi

print "==> Driving discovery, download, replacement, and relaunch"
STATUS_FILE="${HARNESS_ROOT}/update-status.txt"
"${INSTALLED_APP}/Contents/MacOS/Broccoli" \
  --update-rehearsal-auto-accept \
  --update-rehearsal-status-file "${STATUS_FILE}" \
  > "${HARNESS_ROOT}/app.log" 2>&1 &
APP_PID=$!

if [[ "${FAULT}" != "none" ]]; then
  FAILED_SAFELY=0
  for _ in {1..30}; do
    if [[ -f "${STATUS_FILE}" ]] && grep -q '^failed|' "${STATUS_FILE}"; then
      FAILED_SAFELY=1
      break
    fi
    sleep 1
  done
  if [[ "${FAILED_SAFELY}" != "1" ]]; then
    print -u2 "Fault ${FAULT} did not produce an actionable failed state."
    [[ -f "${STATUS_FILE}" ]] && sed -n '1,20p' "${STATUS_FILE}" >&2
    sed -n '1,120p' "${HARNESS_ROOT}/app.log" >&2
    exit 1
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INSTALLED_APP}/Contents/Info.plist")" == "1" ]] || { print -u2 "Fault ${FAULT} partially replaced the baseline."; exit 1; }
  codesign --verify --deep --strict "${INSTALLED_APP}"
  kill -0 "${APP_PID}" >/dev/null 2>&1 || { print -u2 "Fault ${FAULT} left the baseline unlaunchable."; exit 1; }
  print "Fault ${FAULT} was rejected; baseline 0.0.1 (1) remains signed and launchable."
  exit 0
fi

UPDATED=0
for _ in {1..90}; do
  if [[ -f "${INSTALLED_APP}/Contents/Info.plist" ]] && \
     [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INSTALLED_APP}/Contents/Info.plist" 2>/dev/null)" == "2" ]]; then
    UPDATED=1
    break
  fi
  sleep 2
done
[[ "${UPDATED}" == "1" ]] || {
  print -u2 "Local update did not reach build 2. App log: ${HARNESS_ROOT}/app.log"
  exit 1
}

codesign --verify --deep --strict "${INSTALLED_APP}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INSTALLED_APP}/Contents/Info.plist")" == "0.0.2" ]] || exit 1

if [[ "${BROCCOLI_TEST_HOMEBREW_ZAP:-0}" == "1" ]]; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --zap --cask broccoli-local-rehearsal
fi

print "Local signed-feed update passed: 0.0.1 (1) -> 0.0.2 (2)."
print "Disposable keychain, app, feed, cask, user defaults, and signing key will now be removed."
