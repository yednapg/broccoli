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

print "==> Verifying application signature"
codesign --verify --deep --strict "${APP_PATH}"

BUILT_ARCHITECTURES="$(lipo -archs "${EXECUTABLE_PATH}")"
if [[ "${VERIFY_UNIVERSAL}" == "1" ]]; then
  if [[ "${BUILT_ARCHITECTURES}" != *arm64* || "${BUILT_ARCHITECTURES}" != *x86_64* ]]; then
    print -u2 "Expected arm64 and x86_64, found: ${BUILT_ARCHITECTURES}"
    exit 1
  fi
fi

print "Verification passed (${BUILT_ARCHITECTURES})."
