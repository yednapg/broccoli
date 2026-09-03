#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/select-xcode.sh"

usage() {
  print -u2 "usage: scripts/release.sh --mode rehearse|publish --version X.Y.Z --build INTEGER --channel stable|beta --priority routine|important|critical --notes FILE --output DIRECTORY"
  exit 2
}

MODE=""
VERSION=""
BUILD_NUMBER=""
CHANNEL=""
PRIORITY=""
NOTES=""
OUTPUT=""

while (( $# > 0 )); do
  case "$1" in
    --mode|--version|--build|--channel|--priority|--notes|--output)
      (( $# >= 2 )) || usage
      case "$1" in
        --mode) MODE="$2" ;;
        --version) VERSION="$2" ;;
        --build) BUILD_NUMBER="$2" ;;
        --channel) CHANNEL="$2" ;;
        --priority) PRIORITY="$2" ;;
        --notes) NOTES="$2" ;;
        --output) OUTPUT="$2" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ "${MODE}" == "rehearse" || "${MODE}" == "publish" ]] || usage
[[ "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || usage
[[ "${BUILD_NUMBER}" =~ '^[1-9][0-9]*$' ]] || usage
[[ "${CHANNEL}" == "stable" || "${CHANNEL}" == "beta" ]] || usage
[[ "${PRIORITY}" == "routine" || "${PRIORITY}" == "important" || "${PRIORITY}" == "critical" ]] || usage
[[ -f "${NOTES}" ]] || { print -u2 "Release notes do not exist: ${NOTES}"; exit 2; }
[[ -n "${OUTPUT}" ]] || usage

OUTPUT="${OUTPUT:A}"
mkdir -p "${OUTPUT}"
if [[ -n "$(find "${OUTPUT}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  print -u2 "Output directory must be empty: ${OUTPUT}"
  exit 1
fi

SPARKLE_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin"
[[ -x "${SPARKLE_BIN}/generate_appcast" && -x "${SPARKLE_BIN}/sign_update" ]] || {
  print -u2 "Sparkle 2.9.6 release tools are missing. Run swift package resolve first."
  exit 1
}

KEY_ACCOUNT="${BROCCOLI_SPARKLE_KEY_ACCOUNT:-dev.gauravpandey.broccoli}"
KEY_ARGUMENTS=(--account "${KEY_ACCOUNT}")
if [[ -n "${BROCCOLI_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  [[ -f "${BROCCOLI_SPARKLE_PRIVATE_KEY_FILE}" ]] || {
    print -u2 "BROCCOLI_SPARKLE_PRIVATE_KEY_FILE does not exist."
    exit 1
  }
  KEY_ARGUMENTS=(--ed-key-file "${BROCCOLI_SPARKLE_PRIVATE_KEY_FILE}")
fi

if [[ -z "${BROCCOLI_SPARKLE_PUBLIC_KEY:-}" ]]; then
  BROCCOLI_SPARKLE_PUBLIC_KEY="$(${SPARKLE_BIN}/generate_keys --account "${KEY_ACCOUNT}" -p | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' | head -1)"
fi
[[ -n "${BROCCOLI_SPARKLE_PUBLIC_KEY}" ]] || {
  print -u2 "A Sparkle public key is required. Set BROCCOLI_SPARKLE_PUBLIC_KEY or import the matching key into Keychain."
  exit 1
}

BETA_NUMBER="${BROCCOLI_BETA_NUMBER:-1}"
[[ "${BETA_NUMBER}" =~ '^[1-9][0-9]*$' ]] || { print -u2 "BROCCOLI_BETA_NUMBER must be a positive integer."; exit 2; }
if [[ "${CHANNEL}" == "beta" ]]; then
  RELEASE_SLUG="${VERSION}-beta.${BETA_NUMBER}"
else
  RELEASE_SLUG="${VERSION}"
fi
TAG="v${RELEASE_SLUG}"
ARCHIVE_NAME="Broccoli-${RELEASE_SLUG}.zip"
ARCHIVE_PATH="${OUTPUT}/${ARCHIVE_NAME}"
NOTES_PATH="${OUTPUT}/${ARCHIVE_NAME:r}.md"
APPCAST_PATH="${OUTPUT}/appcast.xml"
FEED_URL="${BROCCOLI_FEED_URL:-https://yednapg.github.io/broccoli/appcast.xml}"
DOWNLOAD_PREFIX="${BROCCOLI_DOWNLOAD_URL_PREFIX:-https://github.com/yednapg/broccoli/releases/download/${TAG}}"

if [[ "${MODE}" == "publish" ]]; then
  [[ "${BROCCOLI_ALLOW_PUBLISH:-}" == "YES" && "${GITHUB_ACTIONS:-}" == "true" ]] || {
    print -u2 "Publishing is fail-closed and only allowed in approved GitHub Actions with BROCCOLI_ALLOW_PUBLISH=YES."
    exit 1
  }
  [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]] || {
    print -u2 "Publishing requires a Developer ID Application identity."
    exit 1
  }
  git -C "${PROJECT_DIR}" diff --quiet && git -C "${PROJECT_DIR}" diff --cached --quiet || {
    print -u2 "Publishing requires a clean checkout."
    exit 1
  }
  [[ "$(git -C "${PROJECT_DIR}" rev-list -n 1 "${TAG}" 2>/dev/null)" == "$(git -C "${PROJECT_DIR}" rev-parse HEAD)" ]] || {
    print -u2 "A signed ${TAG} tag must already point to HEAD."
    exit 1
  }
  git -C "${PROJECT_DIR}" tag -v "${TAG}"
  gh auth status
  ! gh release view "${TAG}" >/dev/null 2>&1 || { print -u2 "Release ${TAG} already exists and will not be replaced."; exit 1; }
  [[ -d "${BROCCOLI_PAGES_CHECKOUT:-}" ]] || { print -u2 "BROCCOLI_PAGES_CHECKOUT is required before publication can be validated."; exit 1; }
  PUBLISHED_APPCAST="${BROCCOLI_PAGES_CHECKOUT}/docs/appcast.xml"
  if [[ -f "${PUBLISHED_APPCAST}" ]]; then
    HIGHEST_PUBLISHED_BUILD="$(grep -Eo 'sparkle:version(>|=")[0-9]+' "${PUBLISHED_APPCAST}" 2>/dev/null | grep -Eo '[0-9]+' | sort -n | tail -1 || true)"
    if [[ -n "${HIGHEST_PUBLISHED_BUILD}" && "${BUILD_NUMBER}" -le "${HIGHEST_PUBLISHED_BUILD}" ]]; then
      print -u2 "Build ${BUILD_NUMBER} is not globally higher than published build ${HIGHEST_PUBLISHED_BUILD}."
      exit 1
    fi
  fi
fi

print "==> Building Broccoli ${VERSION} (${BUILD_NUMBER})"
BUILD_ENV=(
  BROCCOLI_VERSION="${VERSION}"
  BROCCOLI_BUILD_NUMBER="${BUILD_NUMBER}"
  BROCCOLI_SPARKLE_PUBLIC_KEY="${BROCCOLI_SPARKLE_PUBLIC_KEY}"
  BROCCOLI_FEED_URL="${FEED_URL}"
)
if [[ "${MODE}" == "publish" ]]; then
  BUILD_ENV+=(BROCCOLI_DISTRIBUTION=1)
else
  BUILD_ENV+=(BROCCOLI_UPDATE_ENV="${BROCCOLI_UPDATE_ENV:-production}")
fi
if [[ -n "${BROCCOLI_BUNDLE_ID:-}" ]]; then
  BUILD_ENV+=(BROCCOLI_BUNDLE_ID="${BROCCOLI_BUNDLE_ID}")
fi
env "${BUILD_ENV[@]}" CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" zsh "${SCRIPT_DIR}/build-app.sh"

APP_PATH="${BROCCOLI_APP_DIR:-${PROJECT_DIR}/build/Broccoli.app}"
BROCCOLI_EXPECTED_VERSION="${VERSION}" BROCCOLI_EXPECTED_BUILD="${BUILD_NUMBER}" \
  "${SCRIPT_DIR}/verify-release.sh" "${APP_PATH}" rehearse
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

NOTARIZATION_ID="not-notarized"
if [[ "${MODE}" == "publish" || "${BROCCOLI_NOTARIZE:-0}" == "1" ]]; then
  [[ -n "${BROCCOLI_NOTARY_PROFILE:-}" ]] || { print -u2 "BROCCOLI_NOTARY_PROFILE is required for notarization."; exit 1; }
  [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]] || { print -u2 "Notarization requires Developer ID signing."; exit 1; }
  NOTARY_RESULT="${OUTPUT}/notarization-result.json"
  xcrun notarytool submit "${ARCHIVE_PATH}" --keychain-profile "${BROCCOLI_NOTARY_PROFILE}" --wait --output-format json > "${NOTARY_RESULT}"
  NOTARIZATION_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "${NOTARY_RESULT}")"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :status' "${NOTARY_RESULT}")" == "Accepted" ]] || { print -u2 "Apple did not accept the notarization submission."; exit 1; }
  xcrun stapler staple "${APP_PATH}"
  rm -f -- "${ARCHIVE_PATH}"
  ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"
  if [[ "${MODE}" == "publish" ]]; then
    BROCCOLI_EXPECTED_VERSION="${VERSION}" BROCCOLI_EXPECTED_BUILD="${BUILD_NUMBER}" \
      "${SCRIPT_DIR}/verify-release.sh" "${APP_PATH}" publish
  else
    xcrun stapler validate "${APP_PATH}"
    spctl --assess --type execute --verbose=2 "${APP_PATH}"
  fi
fi
cp "${NOTES}" "${NOTES_PATH}"

APPCAST_ARGUMENTS=(
  --maximum-deltas 0
  --maximum-versions 0
  --download-url-prefix "${DOWNLOAD_PREFIX}"
  --release-notes-url-prefix "${DOWNLOAD_PREFIX}"
  --versions "${BUILD_NUMBER}"
  -o "${APPCAST_PATH}"
)
if [[ "${MODE}" == "publish" && -f "${PUBLISHED_APPCAST:-}" ]]; then
  cp "${PUBLISHED_APPCAST}" "${APPCAST_PATH}"
elif [[ -n "${BROCCOLI_BASE_APPCAST:-}" ]]; then
  [[ -f "${BROCCOLI_BASE_APPCAST}" ]] || { print -u2 "BROCCOLI_BASE_APPCAST does not exist."; exit 1; }
  cp "${BROCCOLI_BASE_APPCAST}" "${APPCAST_PATH}"
fi
if [[ "${CHANNEL}" == "beta" ]]; then
  APPCAST_ARGUMENTS+=(--channel beta)
elif [[ "${PRIORITY}" == "routine" ]]; then
  APPCAST_ARGUMENTS+=(--phased-rollout-interval 86400)
elif [[ "${PRIORITY}" == "important" ]]; then
  APPCAST_ARGUMENTS+=(--phased-rollout-interval 21600)
fi
if [[ "${PRIORITY}" == "critical" ]]; then
  APPCAST_ARGUMENTS+=(--critical-update-version "")
fi
if [[ "${BROCCOLI_INFORMATIONAL_UPDATE:-0}" == "1" ]]; then
  APPCAST_ARGUMENTS+=(--informational-update-versions "" --link "https://github.com/yednapg/broccoli/releases/tag/${TAG}")
fi

print "==> Generating signed full-archive appcast"
"${SPARKLE_BIN}/generate_appcast" "${KEY_ARGUMENTS[@]}" "${APPCAST_ARGUMENTS[@]}" "${OUTPUT}"
"${SCRIPT_DIR}/set-appcast-priority.pl" "${APPCAST_PATH}" "${BUILD_NUMBER}" "${PRIORITY}"
"${SPARKLE_BIN}/sign_update" "${KEY_ARGUMENTS[@]}" "${APPCAST_PATH}" >/dev/null
"${SPARKLE_BIN}/sign_update" "${KEY_ARGUMENTS[@]}" --verify "${APPCAST_PATH}"

ARCHIVE_SHA="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
APPCAST_SIGNATURE="$(sed -n 's/^edSignature: //p' "${APPCAST_PATH}" | tail -1)"
COMMIT_SHA="$(git -C "${PROJECT_DIR}" rev-parse HEAD)"
MANIFEST_PATH="${OUTPUT}/release-manifest.json"
MANIFEST_PLIST="${OUTPUT}/release-manifest.plist"
/usr/bin/plutil -create xml1 "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :commitSHA string ${COMMIT_SHA}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :version string ${VERSION}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :build integer ${BUILD_NUMBER}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :channel string ${CHANNEL}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :priority string ${PRIORITY}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :archiveSHA256 string ${ARCHIVE_SHA}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :appcastSignature string ${APPCAST_SIGNATURE}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :releaseURL string https://github.com/yednapg/broccoli/releases/tag/${TAG}" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :appcastURL string https://yednapg.github.io/broccoli/appcast.xml" "${MANIFEST_PLIST}"
/usr/libexec/PlistBuddy -c "Add :notarizationID string ${NOTARIZATION_ID}" "${MANIFEST_PLIST}"
/usr/bin/plutil -convert json -o "${MANIFEST_PATH}" "${MANIFEST_PLIST}"
rm -f -- "${MANIFEST_PLIST}"

"${SCRIPT_DIR}/generate-casks.sh" \
  --version "${RELEASE_SLUG}" \
  --sha256 "${ARCHIVE_SHA}" \
  --url "${DOWNLOAD_PREFIX}/${ARCHIVE_NAME}" \
  --channel "${CHANNEL}" \
  --output "${OUTPUT}"

if [[ "${MODE}" == "publish" ]]; then
  print "==> Publishing immutable GitHub release"
  gh release create "${TAG}" "${ARCHIVE_PATH}" "${NOTES_PATH}" "${MANIFEST_PATH}" --verify-tag --notes-file "${NOTES}"
  gh release view "${TAG}" --json url,tagName >/dev/null

  [[ -d "${BROCCOLI_PAGES_CHECKOUT:-}" ]] || { print -u2 "BROCCOLI_PAGES_CHECKOUT is required for the appcast publication step."; exit 1; }
  cp "${APPCAST_PATH}" "${BROCCOLI_PAGES_CHECKOUT}/docs/appcast.xml"
  git -C "${BROCCOLI_PAGES_CHECKOUT}" add docs/appcast.xml
  git -C "${BROCCOLI_PAGES_CHECKOUT}" commit -m "Publish Broccoli ${RELEASE_SLUG} appcast"
  git -C "${BROCCOLI_PAGES_CHECKOUT}" push

  [[ -d "${BROCCOLI_TAP_CHECKOUT:-}" ]] || { print -u2 "BROCCOLI_TAP_CHECKOUT is required for the Homebrew publication step."; exit 1; }
  mkdir -p "${BROCCOLI_TAP_CHECKOUT}/Casks"
  CASK_NAME="broccoli.rb"
  [[ "${CHANNEL}" == "beta" ]] && CASK_NAME="broccoli@beta.rb"
  cp "${OUTPUT}/${CASK_NAME}" "${BROCCOLI_TAP_CHECKOUT}/Casks/${CASK_NAME}"
  git -C "${BROCCOLI_TAP_CHECKOUT}" add "Casks/${CASK_NAME}"
  git -C "${BROCCOLI_TAP_CHECKOUT}" commit -m "Update ${CASK_NAME:r} to ${RELEASE_SLUG}"
  git -C "${BROCCOLI_TAP_CHECKOUT}" push
fi

print "Release artifacts ready in ${OUTPUT}"
[[ "${MODE}" == "rehearse" ]] && print "Rehearsal completed without tags, releases, deployments, tap commits, or pushes."
