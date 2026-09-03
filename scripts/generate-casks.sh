#!/bin/zsh
set -euo pipefail

VERSION=""
SHA256=""
URL=""
CHANNEL=""
OUTPUT=""
while (( $# > 0 )); do
  case "$1" in
    --version) VERSION="$2" ;;
    --sha256) SHA256="$2" ;;
    --url) URL="$2" ;;
    --channel) CHANNEL="$2" ;;
    --output) OUTPUT="$2" ;;
    *) print -u2 "Unknown cask option: $1"; exit 2 ;;
  esac
  shift 2
done
[[ -n "${VERSION}" && "${SHA256}" =~ '^[0-9a-f]{64}$' && -n "${URL}" ]] || { print -u2 "Invalid cask inputs."; exit 2; }
[[ "${CHANNEL}" == "stable" || "${CHANNEL}" == "beta" ]] || exit 2
mkdir -p "${OUTPUT}"

if [[ "${CHANNEL}" == "beta" ]]; then
  TOKEN="broccoli@beta"
  NAME="Broccoli Beta"
else
  TOKEN="broccoli"
  NAME="Broccoli"
fi
CASK_PATH="${OUTPUT}/${TOKEN}.rb"

print -r -- "cask \"${TOKEN}\" do" > "${CASK_PATH}"
print -r -- "  arch arm: \"arm64\"" >> "${CASK_PATH}"
print -r -- "  version \"${VERSION}\"" >> "${CASK_PATH}"
print -r -- "  sha256 arm: \"${SHA256}\"" >> "${CASK_PATH}"
print -r -- "" >> "${CASK_PATH}"
print -r -- "  url \"${URL}\"" >> "${CASK_PATH}"
print -r -- "  name \"${NAME}\"" >> "${CASK_PATH}"
print -r -- "  desc \"Fast, private launcher for macOS\"" >> "${CASK_PATH}"
print -r -- "  homepage \"https://github.com/yednapg/broccoli\"" >> "${CASK_PATH}"
print -r -- "  auto_updates true" >> "${CASK_PATH}"
print -r -- "  depends_on arch: :arm64" >> "${CASK_PATH}"
print -r -- "  depends_on macos: :tahoe" >> "${CASK_PATH}"
if [[ "${CHANNEL}" == "beta" ]]; then
  print -r -- "  conflicts_with cask: \"broccoli\"" >> "${CASK_PATH}"
else
  print -r -- "  conflicts_with cask: \"broccoli@beta\"" >> "${CASK_PATH}"
fi
print -r -- "" >> "${CASK_PATH}"
print -r -- "  app \"Broccoli.app\"" >> "${CASK_PATH}"
print -r -- "" >> "${CASK_PATH}"
print -r -- "  uninstall quit: \"dev.gauravpandey.broccoli\"" >> "${CASK_PATH}"
print -r -- "  zap trash: [" >> "${CASK_PATH}"
print -r -- "    \"~/Library/Application Support/Broccoli\"," >> "${CASK_PATH}"
print -r -- "    \"~/Library/Preferences/dev.gauravpandey.broccoli.plist\"," >> "${CASK_PATH}"
print -r -- "    \"~/Library/Caches/dev.gauravpandey.broccoli\"," >> "${CASK_PATH}"
print -r -- "    \"~/Library/Saved Application State/dev.gauravpandey.broccoli.savedState\"," >> "${CASK_PATH}"
print -r -- "  ]" >> "${CASK_PATH}"
print -r -- "end" >> "${CASK_PATH}"
