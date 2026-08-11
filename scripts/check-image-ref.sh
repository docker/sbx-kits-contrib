#!/usr/bin/env bash
# Assert that every kit which builds its own base image declares that image
# somewhere CI can actually publish it.
#
# Usage:
#   scripts/check-image-ref.sh <registry>/<namespace> [rolling-tag]
#
#   scripts/check-image-ref.sh docker.io/sbx
#   scripts/check-image-ref.sh docker.io/sbx latest
#
# The invariant: a kit directory containing a `Dockerfile` publishes its own
# image, so its `sandbox.image` MUST be
# `<registry>/<namespace>/<kit>-image[:<tag>]`. Kits without a Dockerfile consume
# someone else's image (a sandbox template, a vendor's published agent) and are
# ignored.
#
# Why this exists: build-image.yml reads `sandbox.image` from the spec and
# publishes exactly that, because a spec is consumed literally — no environment
# interpolation — so it cannot follow the workflow's variables. This check is the
# guard on that trust: it stops a spec from pointing the pipeline at a namespace
# it has no business pushing to, and catches a spec left behind on an old
# namespace when REGISTRY/IMAGE_NAMESPACE move.
#
# The `-image` suffix is not decoration: it leaves `<namespace>/<kit>-kit` free
# for the kit artifact itself, once kits are distributed as OCI artifacts too.
#
# The name is DERIVED from the kit directory rather than looked up in a table.
# An enumerated list of expected names would be one more thing to leave stale —
# deriving it cannot go stale, because the directory being checked is the same
# one the name is computed from.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <registry>/<namespace> [rolling-tag]" >&2
  exit 2
fi

prefix=${1%/}          # tolerate a trailing slash
want_tag=${2:-}        # optional: also pin the tag the spec must reference

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Extract the `image:` value from under the `sandbox:` block. Deliberately awk
# rather than a YAML parser: this runs as an early fail-fast CI step, before the
# repo's Go tooling is necessarily set up (see scripts/README.md).
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

echo "Namespace CI can publish to: ${prefix}"
[ -n "$want_tag" ] && echo "Expected rolling tag: ${want_tag}"

checked=0
failed=0

for dockerfile in "$REPO_ROOT"/*/Dockerfile; do
  [ -f "$dockerfile" ] || continue
  kit_dir=$(dirname "$dockerfile")
  kit=$(basename "$kit_dir")

  spec="$kit_dir/spec.yaml"
  [ -f "$spec" ] || spec="$kit_dir/spec.yml"
  if [ ! -f "$spec" ]; then
    # A Dockerfile with no spec is not a kit; the build workflow ignores it too.
    continue
  fi

  checked=$((checked + 1))
  image=$(spec_image "$spec")

  if [ -z "$image" ]; then
    failed=$((failed + 1))
    echo >&2 "error: ${kit} ships a Dockerfile but its spec declares no sandbox.image — CI has nothing to publish it as"
    continue
  fi

  repo=${image%%@*}
  repo=${repo%:*}
  tag=${image#"$repo"}
  tag=${tag#:}

  case "$repo" in
    "$prefix"/*) ;;
    *)
      failed=$((failed + 1))
      cat >&2 <<EOF

error: ${kit}/spec.yaml points at an image CI cannot publish

  sandbox.image : ${image}
    (repository): ${repo}
  publishable   : ${prefix}/*

A kit that ships a Dockerfile is built and pushed by this repository, so its
image must live in the namespace CI authenticates to. Either move the image
under ${prefix}/, or update the REGISTRY / IMAGE_NAMESPACE repository variables
if the namespace itself has moved.
EOF
      continue
      ;;
  esac

  want_name="${kit}-image"
  if [ "${repo##*/}" != "$want_name" ]; then
    failed=$((failed + 1))
    cat >&2 <<EOF

error: ${kit}/spec.yaml declares image name '${repo##*/}', expected '${want_name}'

  sandbox.image : ${image}
  expected      : ${prefix}/${want_name}$([ -n "$want_tag" ] && echo ":${want_tag}")

A kit that publishes its own image names it after the kit directory, with an
'-image' suffix. The suffix keeps '${prefix}/${kit}-kit' free for the kit
artifact itself. Rename the image in the spec, or rename the kit directory if
that is the one that is wrong.
EOF
    continue
  fi

  if [ -n "$want_tag" ] && [ -n "$tag" ] && [ "$tag" != "$want_tag" ]; then
    failed=$((failed + 1))
    cat >&2 <<EOF

error: ${kit}/spec.yaml references tag '${tag}', but CI publishes the rolling tag '${want_tag}'

  sandbox.image : ${image}

The spec would resolve to a tag this pipeline never pushes. Either change the
spec's tag to '${want_tag}', or update the IMAGE_TAG_LATEST variable.
EOF
    continue
  fi

  echo "ok: ${kit}/spec.yaml -> ${image}"
done

if [ "$failed" -gt 0 ]; then
  echo >&2 "${failed} kit(s) declare an unpublishable image."
  exit 1
fi

if [ "$checked" -eq 0 ]; then
  echo "notice: no kit ships a Dockerfile — nothing to verify"
fi

echo "ok: ${checked} image-publishing kit(s) verified"
