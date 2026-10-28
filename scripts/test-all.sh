#!/usr/bin/env bash
# Runs the whole lab: both clouds, Istio, the five checks, and the teardown
# (always, unless KEEP=1). Prints the elapsed time of each step.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

cleanup() {
  if [ "${KEEP:-0}" != 1 ]; then
    bash "${REPO_ROOT}/scripts/teardown.sh" || echo "teardown reported leftovers: check the output above"
  fi
}
trap cleanup EXIT

total=0
for s in 01-infra 02-istio 03-discovery 04-trust 05-locality 06-failover 07-exposure; do
  start=$(date +%s)
  bash "${REPO_ROOT}/scripts/${s}.sh"
  t=$(( $(date +%s) - start ))
  total=$((total + t))
  printf '    %s: %ss\n' "${s}" "${t}"
done
printf '\nall steps passed in %ss (teardown not included)\n' "${total}"
