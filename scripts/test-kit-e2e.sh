#!/usr/bin/env bash
# Run the e2e TCK suite (`TestE2EKit`) against one kit, using a real
# installed `sbx` CLI to create a sandbox and assert that the kit's declared
# content actually lands inside it.
#
# Usage:
#   scripts/test-kit-e2e.sh <kit-dir>         # from repo root
#   ../scripts/test-kit-e2e.sh                # from inside the kit's directory
#   ../scripts/test-kit-e2e.sh my-other-kit   # also works
#
# What the script does for you (so the author doesn't have to):
#   - Scopes every sbx call to APP_NAME=sbx-kits-contrib-tck so the test
#     daemon, sandboxes, policy, and cache are isolated from your main
#     sbx state. Nothing the script does touches your day-to-day daemon.
#     The Go harness uses the same app-name internally (tck/e2e_test.go).
#   - Sets the scoped daemon's default network policy to `deny-all` so
#     the run is a real contract test of network.allowedDomains — the same
#     baseline CI runs under.
#   - Runs `go test -tags=e2e ./tck/...` with KIT_UNDER_TEST exported.
#   - On failure, prints how to read `sbx policy log` to find the missing
#     domains.
#
# The script is idempotent (every step is a write that yields the same
# outcome on repeat runs) and non-interactive (no prompts; relies on
# `-f` / `--force` for the few sbx commands that would otherwise prompt).
#
# Prerequisites (one-time per machine):
#   - `sbx` on PATH. Install from docker/sbx-releases.
#   - The scoped daemon must be logged in to Docker Hub:
#         sbx --app-name sbx-kits-contrib-tck login
#     Each --app-name has its own credential store; this is separate from
#     any login on your main daemon.
#   - On Linux: a Secret Service provider for libsecret (gnome-keyring,
#     kwallet, etc.). Not needed on macOS.
#
# Overrides (env vars):
#   APP_NAME — change the app-name (default: sbx-kits-contrib-tck). Must
#              stay in sync with the Go harness's app-name if you change it.
#   POLICY   — change the default network policy applied to the scoped
#              daemon (default: deny-all). Set POLICY= (empty) to skip
#              the policy step entirely.
#
# Mirrors scripts/test-kit.sh — keep the resolution logic in sync.

set -euo pipefail

APP_NAME=${APP_NAME:-sbx-kits-contrib-tck}
POLICY=${POLICY-deny-all}

# Locate the repo root from the script's own location so the command works
# regardless of where it's invoked from.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Resolve the kit directory. The first positional arg is the kit (relative
# to $PWD, relative to the repo root, or absolute). If the first arg is a
# flag (starts with `-`) or absent, default to $PWD so authors can just run
# `../scripts/test-kit-e2e.sh -v` from inside their kit directory.
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  kit_arg=$1
  shift
else
  kit_arg=$PWD
fi

# Allow either an absolute path or a path relative to repo root or CWD.
if [ -d "$kit_arg" ]; then
  kit_abs=$(cd "$kit_arg" && pwd)
elif [ -d "$REPO_ROOT/$kit_arg" ]; then
  kit_abs=$(cd "$REPO_ROOT/$kit_arg" && pwd)
else
  echo "kit directory not found: $kit_arg" >&2
  exit 1
fi

if [ ! -f "$kit_abs/spec.yaml" ] && [ ! -f "$kit_abs/spec.yml" ]; then
  echo "no spec.yaml/spec.yml in $kit_abs — is this a kit directory?" >&2
  exit 1
fi

if ! command -v sbx >/dev/null 2>&1; then
  echo "sbx not on PATH — install from https://github.com/docker/sbx-releases" >&2
  exit 1
fi

# Smoke test — fail fast if the scoped daemon can't talk to the runtime.
# The most common cause is "not logged in to Docker Hub" (sbx create then
# fails ~minutes into the test), but the same probe also catches a dead
# daemon, KVM access issues, etc. `sbx ls` exercises the runtime and is
# a no-op when everything is fine, making it safe to run unconditionally.
probe_err=$(sbx --app-name "$APP_NAME" ls 2>&1 >/dev/null) || {
  cat >&2 <<EOF
ERROR: smoke test failed — sbx --app-name $APP_NAME is not usable.

$probe_err

Most common fix: the scoped daemon has its own credential store, separate
from any login on your main sbx daemon. Run this one-time setup, then
re-run this script:

  sbx --app-name $APP_NAME login

EOF
  exit 1
}
unset probe_err

# Configure the scoped daemon's global network policy. `policy init` is
# one-time per daemon (sbx errors with "already initialized" on the second
# call), so to stay idempotent we try `init` first and fall back to
# `reset --force` + `init` when a policy is already set — that lands the
# scoped daemon on the desired baseline regardless of prior state. The
# `--force` skips the confirmation prompt about stopping running sandboxes
# (we don't keep any across runs). Skipped when POLICY is explicitly set
# to the empty string.
if [ -n "$POLICY" ]; then
  echo "Initializing --app-name=$APP_NAME global policy to $POLICY"
  if ! sbx --app-name "$APP_NAME" policy init "$POLICY" >/dev/null 2>&1; then
    sbx --app-name "$APP_NAME" policy init "$POLICY"
  fi
fi

# Helper hint on failure — the most common e2e failure is a missing entry
# in network.allowedDomains, which `sbx policy log` surfaces precisely. Wired
# as an EXIT trap (not ERR) so the hint also fires when `set -e` aborts
# mid-test. Only fires on non-zero exit.
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    cat >&2 <<EOF

e2e test failed (exit $rc). To see which hosts the proxy blocked under '${POLICY:-current default}':

  sbx --app-name $APP_NAME ls                              # find the tck-e2e-* sandbox
  sbx --app-name $APP_NAME policy log <sandbox-name>

Every row under 'Blocked requests' is a host your kit reached for. Add it
to network.allowedDomains in spec.yaml and re-run this script.

If the scoped daemon is wedged, wipe it (your main sbx is unaffected):

  sbx --app-name $APP_NAME reset --force

If you haven't logged in to the scoped daemon yet:

  sbx --app-name $APP_NAME login

EOF
  fi
  exit "$rc"
}
trap on_exit EXIT

cd "$REPO_ROOT"
# Focus on TestE2EKit. The ./tck/... package also contains TCK unit tests
# (TestDerive*, TestRunValidationTests, etc.) that are not e2e; running
# them here just spams output. The author can override with `-run …` since
# extra flags are forwarded after this script's args.
KIT_UNDER_TEST="$kit_abs" go test -tags=e2e -v -count=1 -timeout 25m -run TestE2EKit "$@" ./tck/...
