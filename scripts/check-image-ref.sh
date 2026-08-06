#!/usr/bin/env bash
# Assert that every kit spec pointing at our own image namespace names an image
# the CI pipeline actually publishes.
#
# Usage:
#   scripts/check-image-ref.sh <registry>/<namespace> <flavour>[,<flavour>…]
#
#   scripts/check-image-ref.sh docker.io/sbx-kits kiro
#   scripts/check-image-ref.sh docker.io/sbx-kits kiro,other   # if more are added
#
# Why this exists: build-image.yml takes its image coordinates from repository
# variables, but a kit's `sandbox.image` cannot — kit specs are consumed
# literally, with no environment interpolation (see spec/types.go, where Image is
# a plain string, and note that `sandbox.build` is declared but not implemented).
# So the same fact lives in two independent places and will drift.
#
# The check discovers kits rather than being told about them: it scans every
# */spec.yaml, ignores specs pointing at third-party images, and for the rest
# requires an exact match against one of the published flavours. That means a new
# kit adopting one of these images is covered with no workflow change, and a spec
# naming a flavour nobody builds fails loudly instead of slipping through.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <registry>/<namespace> <flavour>[,<flavour>...]" >&2
  exit 2
fi

prefix=${1%/}   # tolerate a trailing slash
flavours=$2

if [ -z "$flavours" ]; then
  echo "error: flavour list must not be empty" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Build the set of fully-qualified repositories CI publishes.
published=""
IFS=',' read -r -a _flavours <<< "$flavours"
for f in "${_flavours[@]}"; do
  [ -n "$f" ] || continue
  published="${published} ${prefix}/${f}"
done

echo "Published repositories:${published}"

# Extract the `image:` value from under the `sandbox:` block of one spec.
# Deliberately a plain awk rather than a YAML parser: this runs as an early
# fail-fast CI step, before the repo's Go tooling is necessarily set up.
spec_image() {
  awk '
    /^sandbox:/      { in_sandbox = 1; next }
    /^[^[:space:]#]/ { in_sandbox = 0 }
    in_sandbox && $1 == "image:" {
      gsub(/^[[:space:]]*image:[[:space:]]*/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$1"
}

checked=0
failed=0

for spec in "$REPO_ROOT"/*/spec.yaml "$REPO_ROOT"/*/spec.yml; do
  [ -f "$spec" ] || continue
  kit=$(basename "$(dirname "$spec")")

  image=$(spec_image "$spec")
  [ -n "$image" ] || continue          # mixins and kits with no sandbox.image

  repo=${image%%@*}
  repo=${repo%:*}

  # A spec is in scope if it sits under our namespace OR names one of our
  # flavours. The second condition matters: matching on the namespace alone would
  # treat a spec left on an OLD namespace as a third-party image and skip it —
  # silently passing exactly the registry/namespace drift this check exists to
  # catch. Kits pointing at genuinely unrelated images (a vendor's own published
  # agent, a sandbox template) match neither condition and are ignored.
  in_scope=false
  case "$image" in "$prefix"/*) in_scope=true ;; esac
  if [ "$in_scope" = false ]; then
    base=${repo##*/}
    for f in "${_flavours[@]}"; do
      if [ "$base" = "$f" ]; then in_scope=true; break; fi
    done
  fi
  [ "$in_scope" = true ] || continue

  checked=$((checked + 1))

  matched=false
  for p in $published; do
    if [ "$repo" = "$p" ]; then matched=true; break; fi
  done

  if [ "$matched" = true ]; then
    echo "ok: ${kit}/spec.yaml -> ${image}"
  else
    failed=$((failed + 1))
    cat >&2 <<EOF

error: ${kit}/spec.yaml references an image this repository does not publish

  sandbox.image  : ${image}
    (repository) : ${repo}
  published      :${published}

Either fix sandbox.image, or add the flavour to the build matrix in
.github/workflows/build-image.yml (and to the flavour list passed to this
script). If the registry or namespace moved, update the REGISTRY /
IMAGE_NAMESPACE repository variables and this spec together.
EOF
  fi
done

if [ "$failed" -gt 0 ]; then
  echo >&2 "${failed} kit spec(s) reference unpublished images."
  exit 1
fi

if [ "$checked" -eq 0 ]; then
  # Legitimate while an image is published before any kit adopts it.
  echo "notice: no kit spec references ${prefix}/* yet — nothing to verify"
fi

echo "ok: ${checked} kit spec(s) verified against published images"
