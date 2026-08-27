#!/bin/zsh

# Source this file from repository scripts so every entry point uses a full Xcode
# toolchain. Command Line Tools do not include the SwiftUI macro plug-in required
# by Broccoli.

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  if [[ ! -d "${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain" ]]; then
    print -u2 "DEVELOPER_DIR does not point to a full Xcode toolchain: ${DEVELOPER_DIR}"
    return 1 2>/dev/null || exit 1
  fi
else
  BROCCOLI_SELECTED_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "${BROCCOLI_SELECTED_DEVELOPER_DIR}" == "/Library/Developer/CommandLineTools" \
    || ! -d "${BROCCOLI_SELECTED_DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain" ]]; then
    BROCCOLI_SELECTED_DEVELOPER_DIR=""
    for BROCCOLI_XCODE_APP in /Applications/Xcode.app /Applications/Xcode-beta.app; do
      if [[ -d "${BROCCOLI_XCODE_APP}/Contents/Developer/Toolchains/XcodeDefault.xctoolchain" ]]; then
        BROCCOLI_SELECTED_DEVELOPER_DIR="${BROCCOLI_XCODE_APP}/Contents/Developer"
        break
      fi
    done
  fi

  if [[ -z "${BROCCOLI_SELECTED_DEVELOPER_DIR}" ]]; then
    print -u2 "Broccoli requires full Xcode; Command Line Tools alone are insufficient."
    print -u2 "Install Xcode or set DEVELOPER_DIR to an Xcode Contents/Developer directory."
    return 1 2>/dev/null || exit 1
  fi
  export DEVELOPER_DIR="${BROCCOLI_SELECTED_DEVELOPER_DIR}"
fi

if [[ "${BROCCOLI_TOOLCHAIN_VERBOSE:-0}" == "1" ]]; then
  print "Using Xcode toolchain: ${DEVELOPER_DIR}"
fi

unset BROCCOLI_SELECTED_DEVELOPER_DIR BROCCOLI_XCODE_APP
