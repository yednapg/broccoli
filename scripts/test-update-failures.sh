#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"

for FAULT in tampered-feed tampered-archive truncated-archive wrong-length offline; do
  print "==> Rehearsing failure: ${FAULT}"
  BROCCOLI_REHEARSAL_FAULT="${FAULT}" zsh "${SCRIPT_DIR}/test-local-update.sh"
done

print "All locally reproducible signed-update failure cases preserved the baseline."

