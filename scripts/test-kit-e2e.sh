#!/usr/bin/env bash
# Run the e2e TCK suite (`TestE2ECreateSandbox`) against one kit, using a real
# installed `sbx` CLI to create a sandbox and assert that the kit's declared
# content actually lands inside it.
#
# Usage:
#   scripts/test-kit-e2e.sh <kit-dir>         # from repo root
#   ../scripts/test-kit-e2e.sh                # from inside the kit's directory
#   ../scripts/test-kit-e2e.sh my-other-kit   # also works
#
# The script resolves <kit-dir> to an absolute path, exports it as
# KIT_UNDER_TEST, and invokes `go test -tags=e2e ./tck/...` against the
# repo-root `tck` package. Extra args (e.g. `-v`, `-run`, `-count=1`) are
# forwarded to `go test`.
#
# Prerequisites (the script does NOT set these up — they're a one-time setup
# for the developer's machine):
#   - `sbx` on PATH (install from docker/sbx-releases)
#   - `sbx login` already run (the test creates a sandbox, which requires auth)
#   - `sbx policy set-default <preset>` already configured
#   - On Linux runners only: a Secret Service provider for libsecret
#     (the CI workflow sets this up via gnome-keyring; not needed on macOS)
#
# Mirrors scripts/test-kit.sh — keep the two in sync when the resolution
# logic changes.

set -euo pipefail

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

cd "$REPO_ROOT"
KIT_UNDER_TEST="$kit_abs" exec go test -tags=e2e -v -count=1 -timeout 25m -run TestE2ECreateSandbox "$@" ./tck/...
