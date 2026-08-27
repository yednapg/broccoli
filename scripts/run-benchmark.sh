#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/select-xcode.sh"
cd "${SCRIPT_DIR:h}"
swift run -c release BroccoliBenchmark
