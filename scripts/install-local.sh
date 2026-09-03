#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_APP="${PROJECT_DIR}/build/Broccoli.app"
APPLICATIONS_DIR="/Applications"
INSTALLED_APP="${APPLICATIONS_DIR}/Broccoli.app"
SOURCE_EXECUTABLE="${SOURCE_APP}/Contents/MacOS/Broccoli"
INSTALLED_EXECUTABLE="${INSTALLED_APP}/Contents/MacOS/Broccoli"
STAGING_APP="${APPLICATIONS_DIR}/.Broccoli.app.installing-$$"
BACKUP_APP="${APPLICATIONS_DIR}/.Broccoli.app.previous-$$"

cleanup() {
  [[ ! -e "${STAGING_APP}" ]] || rm -rf -- "${STAGING_APP}"
  if [[ -e "${BACKUP_APP}" && ! -e "${INSTALLED_APP}" ]]; then
    mv "${BACKUP_APP}" "${INSTALLED_APP}"
  fi
}
trap cleanup EXIT

stop_running_copy() {
  local label="$1"
  local executable="$2"
  local process_pattern="^${executable}([[:space:]].*)?$"

  pgrep -f "${process_pattern}" >/dev/null 2>&1 || return 0
  print "==> Quitting ${label} Broccoli"
  pkill -TERM -f "${process_pattern}"
  for _ in {1..50}; do
    pgrep -f "${process_pattern}" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  print -u2 "The ${label} Broccoli instance did not quit. The verified build was not installed."
  return 1
}

print "==> Verifying Broccoli"
VERIFY_UNIVERSAL=0 zsh "${SCRIPT_DIR}/verify.sh"

[[ -d "${SOURCE_APP}" ]] || {
  print -u2 "Verified build is missing: ${SOURCE_APP}"
  exit 1
}
codesign --verify --deep --strict "${SOURCE_APP}"

print "==> Preparing ${INSTALLED_APP}"
ditto "${SOURCE_APP}" "${STAGING_APP}"
codesign --verify --deep --strict "${STAGING_APP}"

stop_running_copy "installed" "${INSTALLED_EXECUTABLE}"
stop_running_copy "build-directory" "${SOURCE_EXECUTABLE}"

[[ ! -e "${BACKUP_APP}" ]] || {
  print -u2 "Refusing to overwrite unexpected backup path: ${BACKUP_APP}"
  exit 1
}
if [[ -e "${INSTALLED_APP}" ]]; then
  mv "${INSTALLED_APP}" "${BACKUP_APP}"
fi
mv "${STAGING_APP}" "${INSTALLED_APP}"
codesign --verify --deep --strict "${INSTALLED_APP}"
[[ ! -e "${BACKUP_APP}" ]] || rm -rf -- "${BACKUP_APP}"

print "==> Relaunching Broccoli"
open "${INSTALLED_APP}"
INSTALLED_PROCESS_PATTERN="^${INSTALLED_EXECUTABLE}([[:space:]].*)?$"
SOURCE_PROCESS_PATTERN="^${SOURCE_EXECUTABLE}([[:space:]].*)?$"
for _ in {1..50}; do
  pgrep -f "${INSTALLED_PROCESS_PATTERN}" >/dev/null 2>&1 && break
  sleep 0.1
done
pgrep -f "${INSTALLED_PROCESS_PATTERN}" >/dev/null 2>&1 || {
  print -u2 "Broccoli did not relaunch from ${INSTALLED_APP}."
  exit 1
}
pgrep -f "${SOURCE_PROCESS_PATTERN}" >/dev/null 2>&1 && {
  print -u2 "A second Broccoli instance is still running from ${SOURCE_APP}."
  exit 1
}

REVISION="$(git -C "${PROJECT_DIR}" rev-parse --short=12 HEAD)"
if [[ -n "$(git -C "${PROJECT_DIR}" status --short)" ]]; then
  print "Installed ${INSTALLED_APP} from ${REVISION} with uncommitted changes. This exact build is not on GitHub."
else
  print "Installed ${INSTALLED_APP} from clean revision ${REVISION}."
fi
