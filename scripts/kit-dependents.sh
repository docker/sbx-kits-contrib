#!/usr/bin/env bash
# Print the kits whose recipe builds on a base kit, as a JSON array.
#
# Usage:
#   scripts/kit-dependents.sh <base>
#
#   scripts/kit-dependents.sh shell   # the kits built on it, e.g. ["a","b"], or []
#   scripts/kit-dependents.sh goose   # a kit nothing builds on: []
#
# A kit depends on <base> when any `<kit>/*.dockerfile` has a line that names
# <registry>/<namespace>/<base> as a `FROM` image or as an `ARG BASE_IMAGE=`
# value. Matching is case-insensitive and allows:
#   * leading whitespace, and `FROM --platform=<anything> <image>`;
#   * a single or double quote after `ARG BASE_IMAGE=`;
#   * the registry prefix, which also accepts `index.docker.io/` when the
#     registry is docker.io or index.docker.io. With no prefix
#     (`sbx/shell`) the image resolves to docker.io, so that form
#     counts only for those two registries.
# The image name must end at `:`, `@`, a quote, whitespace or the end of the
# line, so `sbx/shell` never matches `sbx/shell-docker` or `sbx/shell-credentials`.
#
# Only discovered kits (scripts/discover-kits.sh, given the same KIT_ROOT) are
# returned, so a stray directory holding a dockerfile never becomes a matrix
# leg. The array is sorted and unique; `[]` when nothing matches, still exit 0.
#
# Environment:
#   REGISTRY          default docker.io
#   IMAGE_NAMESPACE   default sbx
#   KIT_ROOT          default repo root   directory holding <kit>/<kit>.yaml
#
# Stdout carries only the JSON array, so a caller can capture it. Anything
# human goes to stderr.
#
# Exit codes: 0 listed (possibly empty) · 1 discovery failed (its message is
# on stderr, nothing on stdout) · 2 usage error.
#
# Why a script: the build workflow needs this to order a dependent after its
# base, and a script can be run and tested outside CI.
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <base>" >&2
  exit 2
fi
base=$1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
KIT_ROOT=$(cd "${KIT_ROOT:-$REPO_ROOT}" && pwd)
REGISTRY=${REGISTRY:-docker.io}
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-sbx}

# Discovery scans the same root as this script, so the two agree on what a kit
# is.
export KIT_ROOT
kits=$("$SCRIPT_DIR/discover-kits.sh") || exit 1

escape() { printf '%s' "$1" | sed 's/[][\.^$*+?(){}|]/\\&/g'; }
ns=$(escape "$IMAGE_NAMESPACE")
reg=$(escape "$REGISTRY")
name=$(escape "$base")
case "$REGISTRY" in
  docker.io | index.docker.io)
    # The prefix is optional: `sbx/shell` resolves to docker.io.
    prefix="((index\\.)?docker\\.io/)?"
    ;;
  *)
    prefix="${reg}/"
    ;;
esac

pattern="^[[:space:]]*(ARG[[:space:]]+BASE_IMAGE=[\"']?|FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?)${prefix}${ns}/${name}(:|@|\"|'|[[:space:]]|\$)"

{
  while IFS= read -r kit; do
    [ -n "$kit" ] || continue
    files=()
    for f in "$KIT_ROOT/$kit"/*.dockerfile; do
      [ -e "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || continue
    if grep -q -i -E "$pattern" -- "${files[@]}"; then
      printf '%s\n' "$kit"
    fi
  done <<<"$kits"
} | sort -u | jq -R . | jq -sc .
