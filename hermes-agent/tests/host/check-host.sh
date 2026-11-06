#!/usr/bin/env bash
# Usage: HERMES_TEST_APP=<isolated-app> bash check-host.sh <mode> <sandbox>
set -euo pipefail
validation_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=${1:?Supply a check mode}
sandbox=${2:?Supply a sandbox name}
validation_app=${HERMES_TEST_APP:-hermes-oauth-test}
if [ ${#validation_app} -gt 20 ]; then
  echo 'HERMES_TEST_APP must be at most 20 characters.' >&2
  exit 2
fi
case "$mode" in state|unbound|catalog|refresh|refresh-request|refresh-json-probe|refresh-form-probe|negative-policy) ;; *) exit 2 ;; esac
command -v sbx >/dev/null || { echo 'Run this on the Mac with sbx installed.' >&2; exit 1; }
sbx --app-name "$validation_app" exec "$sandbox" -- \
  sh -lc 'kit_python="$HOME/.local/bin/hermes-kit-python"; if [ -L "$kit_python" ]; then kit_python=$(readlink "$kit_python"); fi; exec "$kit_python" - "$@"' sh "$mode" \
  < "$validation_root/check.py"
