#!/usr/bin/env bash
# Run the shared TCK suite against one kit.
#
# Usage:
#   scripts/test-kit.sh <kit-dir>         # from repo root
#   ../scripts/test-kit.sh                # from inside the kit's directory
#   ../scripts/test-kit.sh my-other-kit   # also works
#
# The script resolves <kit-dir> to an absolute path, exports it as KIT, and
# invokes `go test ./tck/...` against the repo-root `tck` package. Extra args
# (e.g. `-v`, `-run`, `-count=1`) are forwarded to `go test`.

set -euo pipefail

# Locate the repo root from the script's own location so the command works
# regardless of where it's invoked from.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Resolve the kit directory. The first positional arg is the kit (relative
# to $PWD, relative to the repo root, or absolute). If the first arg is a
# flag (starts with `-`) or absent, default to $PWD so authors can just run
# `../scripts/test-kit.sh -v` from inside their kit directory.
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

cd "$REPO_ROOT"

# A kind:sandbox kit may build its own base image rather than consuming a
# published one. The TCK's `container` subtest starts `sandbox.image`, so for
# those kits it must test the image THIS working tree produces — not whatever
# happens to be published under that tag.
#
# Without this the subtest would either pull a stale image (silently ignoring a
# Dockerfile change in the branch) or fail outright with "pull access denied"
# when the image has not been published yet, which is the normal state while a
# kit is being introduced.
#
# Build failures are fatal: a kit that cannot build its own base image is broken.
# Set SBX_KIT_SKIP_IMAGE_BUILD=1 to reuse an already-built local image instead.
if [ -f "$kit_abs/Dockerfile" ] && [ -z "${SBX_KIT_SKIP_IMAGE_BUILD:-}" ]; then
  spec_file="$kit_abs/spec.yaml"
  [ -f "$spec_file" ] || spec_file="$kit_abs/spec.yml"

  # Read sandbox.image with awk rather than a YAML parser to keep this script
  # dependency-free (see scripts/README.md).
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

  if [ -n "$kit_image" ]; then
    echo "==> building $(basename "$kit_abs")/Dockerfile as ${kit_image}"
    docker build -t "$kit_image" "$kit_abs"
  else
    echo "==> $(basename "$kit_abs") has a Dockerfile but no sandbox.image; skipping build" >&2
  fi
fi

KIT="$kit_abs" exec go test -v -count=1 -timeout 10m -run TestKitTCK "$@" ./tck/...
