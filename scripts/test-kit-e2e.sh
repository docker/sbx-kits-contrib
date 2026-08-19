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
#   - For a kit that ships its own Dockerfile: builds that image and
#     side-loads it into the scoped daemon's image store, so e2e runs against
#     the image this working tree produces rather than a published one (or
#     none at all). Skip with SBX_KIT_SKIP_IMAGE_LOAD=1.
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
#     any login on your main daemon. On Linux, sbx uses a Secret Service
#     provider for libsecret when one is available (gnome-keyring, kwallet,
#     etc.), and otherwise falls back to an encrypted on-disk store — no
#     Secret Service setup is required.
#
# Overrides (env vars):
#   APP_NAME — change the app-name (default: sbx-kits-contrib-tck). Must
#              stay in sync with the Go harness's app-name if you change it.
#   SBX_KIT_SKIP_IMAGE_LOAD — set to 1 to skip building and side-loading a
#              Dockerfile-shipping kit's image, and use whatever the store
#              already has (or the published image) instead.
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

# A kit that ships its own Dockerfile builds the image the sandbox boots from,
# and sbx resolves that image from ITS OWN image store — not from the host's
# Docker daemon. So for such a kit there are two independent reasons e2e can
# fail before the kit is exercised at all:
#
#   1. The image was never published, so the pull 403s/404s.
#   2. The image WAS published, but this branch changed the Dockerfile — the
#      pull then returns the old published image and the change goes untested.
#
# Both are fixed the same way: build the kit's image here and side-load it into
# the scoped daemon's store, so e2e always runs against the image this working
# tree produces. This is the e2e counterpart of the build that scripts/test-kit.sh
# does for the TCK; without it, a first-of-its-kind kit cannot be e2e-tested
# until its registry repository exists.
#
# Only kits with a Dockerfile are affected. Set SBX_KIT_SKIP_IMAGE_LOAD=1 to
# skip this and use whatever the store already has (or the published image).
if [ -f "$kit_abs/Dockerfile" ] && [ -z "${SBX_KIT_SKIP_IMAGE_LOAD:-}" ]; then
  spec_file="$kit_abs/spec.yaml"
  [ -f "$spec_file" ] || spec_file="$kit_abs/spec.yml"

  # Read sandbox.image with awk rather than a YAML parser to keep this script
  # dependency-free (see scripts/README.md). Same extractor as test-kit.sh and
  # check-image-ref.sh — keep the three in sync.
  kit_image=$(awk '
    /^sandbox:/      { in_sandbox = 1; next }
    /^[^[:space:]#]/ { in_sandbox = 0 }
    in_sandbox && $1 == "image:" {
      gsub(/^[[:space:]]*image:[[:space:]]*/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$spec_file")

  if [ -z "$kit_image" ]; then
    echo "ERROR: $(basename "$kit_abs") ships a Dockerfile but declares no sandbox.image" >&2
    exit 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required to build $(basename "$kit_abs")'s image for e2e." >&2
    echo "       Set SBX_KIT_SKIP_IMAGE_LOAD=1 to use the published image instead." >&2
    exit 1
  fi

  echo "==> building $(basename "$kit_abs")/Dockerfile as ${kit_image}"
  docker build -t "$kit_image" "$kit_abs"

  # sbx imports from a tar, not from the host daemon's store, so the image has
  # to be exported first. These tars are the whole image and can be gigabytes,
  # so the file is removed on every path below.
  #
  # Deliberately NOT cleaned up via `trap ... EXIT`: this script installs an
  # EXIT trap further down (on_exit, which prints the policy-log hint), and bash
  # keeps only one EXIT trap — registering one here would be silently replaced
  # and the tar would leak. Explicit removal on both the success and failure
  # path is unambiguous.
  # Full template path, not `mktemp -t PREFIX`: BSD/macOS mktemp treats the -t
  # argument as a prefix and appends its own randomness, leaving any XXXXXX in
  # the middle literal (producing e.g. `sbx-kit-image-XXXXXX.tar.ZgE4cn4lKW`),
  # while GNU mktemp substitutes it. Passing a path template with the XXXXXX
  # last behaves identically on both.
  image_tar=$(mktemp "${TMPDIR:-/tmp}/sbx-kit-image-XXXXXX") || {
    echo "ERROR: could not create a temp file for the image export" >&2
    exit 1
  }
  echo "==> exporting ${kit_image} for import into the --app-name=$APP_NAME store"
  echo "==> loading ${kit_image} into the --app-name=$APP_NAME image store"
  load_rc=0
  {
    docker save "$kit_image" -o "$image_tar" &&
      sbx --app-name "$APP_NAME" template load "$image_tar"
  } || load_rc=$?
  rm -f "$image_tar"
  if [ "$load_rc" -ne 0 ]; then
    echo "ERROR: could not load ${kit_image} into the --app-name=$APP_NAME store." >&2
    echo "       Set SBX_KIT_SKIP_IMAGE_LOAD=1 to skip and use the published image." >&2
    exit "$load_rc"
  fi

  # Verify the tag survived the round trip. `sbx create` resolves the spec's
  # image reference verbatim, so if the import landed the image under a
  # different name the test still fails at PREPARE IMAGE — with a confusing
  # 403 rather than anything pointing here. Warn rather than fail: `template
  # ls` output is not a contract, and a false negative here should not block a
  # run that would otherwise work.
  if ! sbx --app-name "$APP_NAME" template ls 2>/dev/null | grep -qF "${kit_image%%:*}"; then
    cat >&2 <<EOF

WARNING: after 'template load', '${kit_image}' was not visible in:
  sbx --app-name $APP_NAME template ls

If the run below fails at PREPARE IMAGE with a pull error, the import likely
stored the image under a different reference. Check the list above and either
retag before saving, or point the kit's sandbox.image at what landed.
EOF
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
