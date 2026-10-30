#!/usr/bin/env bash
# Check that a workload kit's built image is one a sandbox can launch.
#
# Usage:
#   scripts/verify-kit-image.sh <kit>
#
#   scripts/verify-kit-image.sh claude                   # build, then check
#   IMAGE=myimage:tag scripts/verify-kit-image.sh claude # check an existing image
#
# For a `kind: workload` kit this builds <kit>/<kit>.yaml for one platform
# (linux/amd64 by default) into the local daemon and asserts, as the image's own user:
#   1. the launch binary (ENTRYPOINT[0], else CMD[0]) resolves on PATH,
#      or is an absolute path a `path:` entry in the kit's descriptor writes;
#   2. the image sets a user and it is not root;
#   3. label com.docker.sandboxes.flavor equals the kit name;
#   4. if label com.docker.sandboxes.start-docker is "true", dockerd, docker
#      and containerd resolve on PATH.
# A `kind: mixin` kit is skipped: its image is an overlay, not a launchable one.
# A `kind: set` kit fails: a set's derived kind is recorded only in the
# published manifest's descriptor annotation, which `--load` does not keep,
# and the authored `kind:` is all this script reads.
#
# Why: the kit frontend copies the recipe's image config as-is (it rejects only
# a workload with neither ENTRYPOINT nor CMD), so a Dockerfile that forgets a
# label or runs as root builds fine.
#
# Environment:
#   IMAGE      optional           check this image, skip the build and the cleanup
#   KIT_ROOT   default repo root  directory holding <kit>/<kit>.yaml
#   BUILDER    optional           --builder, for a named buildx builder
#   CACHE_FROM optional           passed to --cache-from
#   NO_CACHE   set to any value   passed as --no-cache
#   VERIFY_PLATFORM default linux/amd64  build platform; set linux/arm64 on an arm64 host
#
# Every failed assertion prints one line naming the kit, the assertion and the
# observed value. All assertions run before the script exits.
#
# Exit codes: 0 verified or skipped · 1 an assertion failed or the build failed ·
# 2 usage error.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <kit>" >&2
  exit 2
fi
kit=$1
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KIT_ROOT=${KIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}
IMAGE=${IMAGE:-}
BUILDER=${BUILDER:-}
CACHE_FROM=${CACHE_FROM:-}
NO_CACHE=${NO_CACHE:-}
VERIFY_PLATFORM=${VERIFY_PLATFORM:-linux/amd64}

descriptor="$KIT_ROOT/$kit/$kit.yaml"
[ -f "$descriptor" ] || descriptor="$KIT_ROOT/$kit/$kit.yml"
if [ ! -f "$descriptor" ]; then
  echo "error: no kit '$kit' under $KIT_ROOT (expected $kit/$kit.yaml)" >&2
  exit 2
fi

# Only a top-level `kind:` counts; the value may be single- or
# double-quoted or carry a comment.
kind=$(sed -n "s/^kind:[[:space:]]*[\"']\{0,1\}\([A-Za-z]*\)[\"']\{0,1\}[[:space:]]*\(#.*\)\{0,1\}\$/\1/p" "$descriptor" | head -n 1)
case "$kind" in
  workload) ;;
  mixin)
    echo "verify-kit-image: $kit is kind 'mixin', not workload; skipping"
    exit 0
    ;;
  set)
    echo "FAIL $kit: kind: set is not verified yet"
    exit 1
    ;;
  *)
    echo "FAIL $kit: kind: '${kind:-(none)}' in $(basename "$descriptor") is neither workload nor mixin"
    exit 1
    ;;
esac

img=$IMAGE
if [ -z "$img" ]; then
  img="sbx-verify/$kit:verify-$$"
  trap 'docker image rm -f "$img" >/dev/null 2>&1 || true' EXIT
  args=(buildx build "$KIT_ROOT/$kit" -f "$descriptor" --platform "$VERIFY_PLATFORM" --load -t "$img")
  if [ -n "$BUILDER" ]; then args+=(--builder "$BUILDER"); fi
  if [ -n "$CACHE_FROM" ]; then args+=(--cache-from "$CACHE_FROM"); fi
  if [ -n "$NO_CACHE" ]; then args+=(--no-cache); fi
  echo "==> docker ${args[*]}"
  docker "${args[@]}" || {
    echo "FAIL $kit: image build failed" >&2
    exit 1
  }
fi

# `if` guards keep the template from aborting on an image with no entrypoint,
# no cmd or no labels at all; the value is then simply empty.
launch=$(docker inspect --format \
  '{{ if .Config.Entrypoint }}{{ index .Config.Entrypoint 0 }}{{ else if .Config.Cmd }}{{ index .Config.Cmd 0 }}{{ end }}' "$img")
user=$(docker inspect --format '{{ .Config.User }}' "$img")
flavor=$(docker inspect --format \
  '{{ if .Config.Labels }}{{ index .Config.Labels "com.docker.sandboxes.flavor" }}{{ end }}' "$img")
start_docker=$(docker inspect --format \
  '{{ if .Config.Labels }}{{ index .Config.Labels "com.docker.sandboxes.start-docker" }}{{ end }}' "$img")

echo "verify-kit-image: kit=$kit launch=${launch:-(none)} user=${user:-(unset)} flavor=${flavor:-(unset)} start-docker=${start_docker:-(unset)}"

fail=0
bad() {
  echo "FAIL $kit: $1"
  fail=1
}

# (a) launch binary, resolved as the image's user.
if [ -z "$launch" ]; then
  bad "launch binary: image sets neither ENTRYPOINT nor CMD"
elif docker run --rm --entrypoint sh "$img" -c 'command -v "$1" >/dev/null' _ "$launch" >/dev/null 2>&1; then
  echo "verify-kit-image: launch binary '$launch' resolves on PATH"
# Exact absolute path only: a `files:` entry writes it at create time,
# so it is absent from the image.
elif [ "${launch#/}" != "$launch" ] &&
  grep -Eq "^[[:space:]]*-?[[:space:]]*path:[[:space:]]*[\"']?$(printf '%s' "$launch" | sed 's/[][\.*^$+?(){}|]/\\&/g')[\"']?[[:space:]]*(#.*)?$" "$descriptor"; then
  echo "verify-kit-image: launch binary '$launch' is written by a path: entry in $(basename "$descriptor")"
else
  bad "launch binary: '$launch' does not resolve on PATH and no path: entry in $(basename "$descriptor") writes it"
fi

# (b) non-root user.
case "$user" in
  "" | root | 0 | 0:* | root:*)
    bad "user: image runs as '${user:-(unset, so root)}', expected a non-root user"
    ;;
esac

# (c) flavor names the kit.
if [ "$flavor" != "$kit" ]; then
  bad "flavor: label com.docker.sandboxes.flavor is '${flavor:-(unset)}', expected '$kit'"
fi

# (d) a start-docker request is backed by an engine.
if [ "$start_docker" = "true" ]; then
  missing=$(docker run --rm --entrypoint sh "$img" -c '
    for bin in dockerd docker containerd; do
      command -v "$bin" >/dev/null || printf "%s " "$bin"
    done' 2>/dev/null) || missing="(could not run sh in the image)"
  if [ -n "$missing" ]; then
    bad "start-docker: label is 'true' but not on PATH: ${missing% }"
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "verify-kit-image: $kit verified"
