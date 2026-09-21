#!/usr/bin/env bash
# Conformance-check one kit against the sandbox kit specification, using the
# spec project's own `kit-tck`.
#
# Usage:
#   scripts/test-kit.sh <kit-dir> [kit-tck flags...]   # from repo root
#   ../scripts/test-kit.sh                            # from inside the kit's directory
#   ../scripts/test-kit.sh my-other-kit -v            # also works
#   scripts/test-kit.sh --ref <reference> [flags...]  # judge a PUBLISHED artifact
#   scripts/test-kit.sh --validate-only <kit-dir>     # descriptor check only, builds nothing
#
# WHY THIS IS A BUILD AND NOT A SOURCE CHECK
#
# Conformance in v3 is a property of the published artifact, not of the YAML that
# produced it. `kit-tck` judges annotations, layers, staged sources and image
# config against the specification, with every check linked to the clause it
# enforces — so it can only run on something built. That is the whole reason this
# script builds: the artifact IS the thing under test.
#
# Two build outputs matter here and this script uses both:
#
#   type=oci,dest=<dir>,tar=false   an OCI layout directory on local disk. No
#                                   registry and no push, which is what makes
#                                   conformance runnable on a PR at all. (The
#                                   BUILD needs no credentials either — the kit
#                                   frontend is anonymously pullable. Installing
#                                   kit-tck does, because the specification
#                                   repository is not public.)
#   type=cacheonly                  build and throw everything away. Used by
#                                   --validate-only: the frontend validates the
#                                   descriptor during the build and fails the
#                                   build on a bad one, so a build that produces
#                                   nothing is still a complete descriptor check.
#                                   There is deliberately no separate "validate
#                                   the YAML" step anywhere in this repo.
#
# Environment:
#   KIT_TCK      path to the kit-tck binary. Default: `kit-tck` on PATH, else
#                $(go env GOPATH)/bin/kit-tck.
#   LAYOUT_TAG   tag the throwaway layout is built under (default: tck).
#   KEEP_LAYOUT  set to 1 to keep the layout directory for post-mortem poking
#                (`jq . <dir>/index.json`) instead of removing it on exit.
#   PLATFORM     value for `docker buildx build --platform`. Default: unset, so
#                the builder picks its native platform. Publishing builds the
#                full platform matrix; a PR check does not need to, and cross
#                building a recipe kit under emulation is minutes per kit.
#   BUILDER      value for `docker buildx build --builder`.
#
# Exit codes: 0 conforms · non-zero build failure, non-conformance, or usage error.

set -euo pipefail

LAYOUT_TAG=${LAYOUT_TAG:-tck}

# Locate the repo root from the script's own location so the command works
# regardless of where it's invoked from.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Resolve kit-tck into $kit_tck, or print the one command that installs it.
#
# Called lazily, only on the paths that actually need it: --validate-only is a
# build and nothing else, and it has to keep working where kit-tck is absent —
# which is exactly the fork-PR leg in CI, since installing kit-tck needs read
# access to a private repository a fork's token does not have.
#
# Deliberately not installed on the caller's behalf: `go install` mutates the
# machine's GOPATH, which a test script has no business doing silently. CI runs the
# same line as its own step, so the install is visible in the job log.
kit_tck=""
resolve_kit_tck() {
  kit_tck=${KIT_TCK:-}
  [ -z "$kit_tck" ] || return 0
  if command -v kit-tck >/dev/null 2>&1; then
    kit_tck=kit-tck
  elif command -v go >/dev/null 2>&1 && [ -x "$(go env GOPATH)/bin/kit-tck" ]; then
    # `go install` lands the binary here whether or not GOPATH/bin is on PATH,
    # which it often is not on a fresh machine.
    kit_tck="$(go env GOPATH)/bin/kit-tck"
  else
    cat >&2 <<'EOF'
ERROR: kit-tck not found. Install the conformance suite:

  go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest

It ships with the specification rather than with this repository on purpose: the
checks and the clauses they enforce version together.

docker/sandbox-kit-spec is not a public repository, so that install needs a git
credential for github.com that can read it, and GOPRIVATE=github.com/docker/* so
the fetch goes to git rather than to the public module proxy.

To check only that a descriptor is valid, which needs no kit-tck at all:

  scripts/test-kit.sh --validate-only <kit-dir>
EOF
    exit 1
  fi
}

# --ref judges an artifact that is already in a registry, which is the form to
# reach for AFTER a publish ("is what we shipped conformant?"). It needs no
# checkout and no build, but it does need pull access: kit-tck reads the Docker
# credential store, and this repo's kit repositories are not anonymously
# pullable, so a `docker login` has to have happened first.
if [ "${1:-}" = "--ref" ]; then
  shift
  [ $# -gt 0 ] || { echo "usage: $0 --ref <reference> [kit-tck flags...]" >&2; exit 2; }
  ref=$1
  shift
  resolve_kit_tck
  echo "==> kit-tck kit ${ref}"
  exec "$kit_tck" kit "$ref" "$@"
fi

validate_only=
if [ "${1:-}" = "--validate-only" ]; then
  validate_only=1
  shift
fi

# Resolve the kit directory. The first positional arg is the kit (relative to
# $PWD, relative to the repo root, or absolute). If the first arg is a flag
# (starts with `-`) or absent, default to $PWD so authors can just run
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

# A v3 kit is a directory whose descriptor is named after it — the same contract
# scripts/discover-kits.sh uses to decide what a kit is, restated here so a typo
# in a hand-typed argument fails with this message instead of a buildx error
# about a missing -f file.
kit_name=$(basename "$kit_abs")
descriptor="$kit_abs/$kit_name.yaml"
if [ ! -f "$descriptor" ]; then
  echo "no $kit_name.yaml in $kit_abs — is this a v3 kit directory?" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required to build ${kit_name} for conformance." >&2
  exit 1
fi

# The kit directory is the build context, and the descriptor is the "Dockerfile".
# The `# syntax=docker/sandbox-kit:3` line at the top of the descriptor is what
# routes the build to the kit frontend; buildx resolves that image anonymously,
# so no registry credentials are involved in a conformance run.
#
# PLATFORM/BUILDER are interpolated with `${VAR:+...}` rather than collected into
# an array: macOS still ships bash 3.2 as /bin/bash, where expanding an EMPTY
# array under `set -u` is an "unbound variable" error. Neither value can contain
# whitespace, so the unquoted expansion is safe.
kit_build() {
  docker buildx build "$kit_abs" \
    -f "$descriptor" \
    ${PLATFORM:+--platform "$PLATFORM"} \
    ${BUILDER:+--builder "$BUILDER"} \
    "$@"
}

if [ -n "$validate_only" ]; then
  echo "==> validating ${kit_name}/${kit_name}.yaml (build to cacheonly)"
  kit_build --output type=cacheonly
  exit 0
fi

# Before the build, not after: a build can take minutes, and discovering only at
# the end that the thing meant to judge it is missing wastes all of them.
resolve_kit_tck

# An existing empty directory is fine as a `dest=` — buildx populates it with
# blobs/, index.json, oci-layout and its own ingest/ scratch space. Full template
# path, not `mktemp -d -t PREFIX`: BSD/macOS mktemp treats the -t argument as a
# prefix and appends its own randomness, leaving any XXXXXX in the middle
# literal, while GNU mktemp substitutes it. A path template with the XXXXXX last
# behaves identically on both.
layout=$(mktemp -d "${TMPDIR:-/tmp}/${kit_name}-layout-XXXXXX") || {
  echo "ERROR: could not create a temp directory for the OCI layout" >&2
  exit 1
}
# A layout is the whole artifact on disk and a recipe kit's can be large, so it
# goes away on every exit path unless the caller asked to keep it.
cleanup() {
  if [ -n "${KEEP_LAYOUT:-}" ]; then
    echo "==> layout kept at ${layout}" >&2
  else
    rm -rf "$layout"
  fi
}
trap cleanup EXIT

echo "==> building ${kit_name} into an OCI layout at ${layout}"
kit_build \
  --output "type=oci,dest=${layout},tar=false" \
  -t "${kit_name}-kit:${LAYOUT_TAG}"

# THE TAG ARGUMENT IS THE TAG ALONE, NOT THE REFERENCE THE BUILD WAS TAGGED WITH.
# `-t <kit>-kit:<tag>` above is a full reference, but an OCI layout records only
# its trailing tag in index.json's org.opencontainers.image.ref.name — so the
# reference that resolves inside the layout is `<tag>`. Passing what was handed
# to `-t` fails with `kit-tck: resolve <kit>-kit:<tag>: not found`, which reads
# like a broken build rather than a wrong argument. This is an easy hour to lose.
#
# The tag itself is a local handle and nothing more, which is why it is a fixed
# string instead of the kit's version: `version:` is optional in v3 and is often
# a `${{ kit.args.version }}` reference the frontend expands during the build, so
# there is frequently no version to read out of the source at all. kit-tck takes
# the real one from the artifact's own org.opencontainers.image.version
# annotation.
#
# A WARNING IS NOT A FAILURE. On a multi-node builder, buildx merges per-node
# results into a fresh index, which drops the kit annotations from the index
# level; SPEC-v3 §9.3 says consumers fall back to the platform manifest, which
# still carries them, so kit-tck reports `index-annotations` as warned and still
# concludes "conforms" with exit 0. Do not add a grep for "warned" here.
echo "==> kit-tck kit --layout ${layout} ${LAYOUT_TAG}"
"$kit_tck" kit --layout "$layout" "$LAYOUT_TAG" "$@"
