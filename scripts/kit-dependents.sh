#!/usr/bin/env bash
# Print the kits whose recipe builds on a base kit, as a JSON array.
#
# Usage:
#   scripts/kit-dependents.sh <base>
#
#   scripts/kit-dependents.sh shell   # the kits built on it, e.g. ["a","b"], or []
#   scripts/kit-dependents.sh goose   # a kit nothing builds on: []
#
# A kit depends on <base> when its recipe has a line that names
# <registry>/<namespace>/<base> as a `FROM` image or as an `ARG BASE_IMAGE=`
# value. The recipe is read the way the kit frontend finds it, so every form
# counts:
#   * the `build:` block in the descriptor (`<kit>/<kit>.yaml` or `.yml`);
#   * the file named by the descriptor's `dockerfile:`, relative to the kit
#     directory (quoted or not, a trailing comment ignored). A path that is
#     absolute, has a `..` component, or names a missing file is skipped: the
#     frontend reports those at build time;
#   * every `<kit>/*.dockerfile`, which covers the companion
#     `<kit>/<kit>.dockerfile` and any further recipe file.
# Only top-level `build:` and `dockerfile:` keys are read, with awk, so the
# descriptor needs no YAML tool on the runner. It is not a YAML parser: a
# tagged or anchored value (`build: !!str |`), a quoted key (`"build":`) and a
# multi-line or escaped double-quoted scalar are not read.
# Matching is case-insensitive and allows:
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

# Print the value of a top-level key of a descriptor. A block scalar
# (`|`, `>-`, ...) prints its lines; a quoted or plain value prints once, with
# a quoted value cut at its closing quote and a plain one at ` #`.
yaml_key() {
  awk -v key="$1" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    inblock {
      if ($0 ~ /^[^ \t\r]/) { inblock = 0 } else { print; next }
    }
    index($0, key ":") == 1 {
      v = trim(substr($0, length(key) + 2))
      if (v ~ /^[|>][-+0-9]*([ \t]+#.*)?$/) { inblock = 1; next }
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        v = substr(v, 2)
        e = index(v, q)
        if (e > 0) v = substr(v, 1, e - 1)
        if (q == "\"") gsub(/\\n/, "\n", v)
      } else {
        sub(/[ \t]+#.*$/, "", v)
      }
      print v
    }
  ' "$2"
}

matches() { grep -i -E "$pattern" >/dev/null; }

builds_on_base() {
  local kit=$1 dir="$KIT_ROOT/$1" desc="" f rel
  for f in "$dir/$kit.yaml" "$dir/$kit.yml"; do
    [ -f "$f" ] && desc=$f && break
  done
  if [ -n "$desc" ]; then
    yaml_key build "$desc" | matches && return 0
    rel=$(yaml_key dockerfile "$desc")
    case "$rel" in
      "" | /* | ../* | */../* | */.. | ..) ;;
      *) [ -f "$dir/$rel" ] && matches <"$dir/$rel" && return 0 ;;
    esac
  fi
  for f in "$dir"/*.dockerfile; do
    [ -f "$f" ] && matches <"$f" && return 0
  done
  return 1
}

{
  while IFS= read -r kit; do
    [ -n "$kit" ] || continue
    if builds_on_base "$kit"; then
      printf '%s\n' "$kit"
    fi
  done <<<"$kits"
} | sort -u | jq -R . | jq -sc .
