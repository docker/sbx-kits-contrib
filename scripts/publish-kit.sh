#!/usr/bin/env bash
# Publish one kit as an OCI image to <registry>/<namespace>/sbx-kit-<kit>.
#
# Usage:
#   scripts/publish-kit.sh <kit>
#
#   DRY_RUN=1 scripts/publish-kit.sh claude      # build it, push nothing
#   scripts/publish-kit.sh claude                # build and push
#
# Environment:
#   REGISTRY          default docker.io
#   IMAGE_NAMESPACE   default docker
#   IMAGE_NAME_PREFIX default sbx-kit-
#   IMAGE_TAG_LATEST  default latest      — the rolling tag's name
#   MOVE_LATEST       default true        — also tag the rolling tag
#   PLATFORMS         default linux/amd64,linux/arm64
#   SBOM_GENERATOR    default dhi.io/scout-sbom-indexer:1
#   BUILDER           optional            — --builder, for a named buildx builder
#   CACHE_FROM        optional            — passed to --cache-from
#   CACHE_TO          optional            — passed to --cache-to
#   NO_CACHE          set to any value    — passed as --no-cache
#   DRY_RUN           set to any value    — build, but publish nothing
#
# Emits `ref=`, `version=`, `tags=` and `pushed=` on stdout, one per line, so CI
# can redirect into $GITHUB_OUTPUT. Everything human goes to stderr, which keeps
# that redirect safe. When GITHUB_STEP_SUMMARY is set, a summary is appended
# there too.
#
# Exit codes: 0 published (or dry run) · 1 refused or failed · 2 usage error.
#
#
# WHAT THIS REPLACED, AND WHY IT IS SO MUCH SHORTER
#
# A v2 kit was a YAML file that POINTED AT an image, so publishing it meant
# shipping two things to two repositories: the base image (`<kit>-image`, built
# from the kit's Dockerfile) and the kit artifact (`<kit>-kit`, packed with
# `sbx kit pack` and pushed with oras). The predecessor of this script existed
# to manage the second of those and the seams around it — an existence probe
# so an immutable tag was never overwritten, a keyless Sigstore signature, a
# digest read-back, and an `oras tag` by digest to move the rolling tag without
# re-packing (a second pack re-stamps org.opencontainers.image.created and
# digests differently, which would have given the two tags different
# attestations for one source).
#
# In v3 a kit IS an image. The descriptor rides in the published image's
# manifest annotation and the layers are its content, so there is exactly one
# thing to push and `docker buildx build --push` pushes it. Every seam above
# closes with it: buildx attaches provenance and SBOM as native attestations,
# and both tags are arguments to ONE invocation, so they cannot be given
# different content — there is no second push to diverge from the first.
#
# The frontend named on the descriptor's first line (`# syntax=docker/sandbox-kit:3`)
# validates the descriptor as part of the build, which is why nothing here
# validates anything. A malformed kit fails the build, in the same place a
# malformed Dockerfile would, rather than in a separate step that could be
# skipped or could drift from what the frontend actually accepts. BuildKit
# pulls that frontend itself, so there is no tool to install first.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <kit>" >&2
  exit 2
fi

kit=$1

REGISTRY=${REGISTRY:-docker.io}
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-docker}
IMAGE_NAME_PREFIX=${IMAGE_NAME_PREFIX:-sbx-kit-}
IMAGE_TAG_LATEST=${IMAGE_TAG_LATEST:-latest}
MOVE_LATEST=${MOVE_LATEST:-true}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}
SBOM_GENERATOR=${SBOM_GENERATOR:-dhi.io/scout-sbom-indexer:1}
BUILDER=${BUILDER:-}
CACHE_FROM=${CACHE_FROM:-}
CACHE_TO=${CACHE_TO:-}
NO_CACHE=${NO_CACHE:-}
DRY_RUN=${DRY_RUN:-}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# The KEY=VALUE stream CI redirects into $GITHUB_OUTPUT moves to fd 3, and this
# script's stdout is rerouted to stderr. Structurally, rather than by appending
# `>&2` to each command: buildx is chatty on both streams, and one stray line in
# $GITHUB_OUTPUT fails the step with "Invalid format" at a distance from its
# cause. With stdout rerouted, no command added later can break that contract by
# accident. Command substitution is unaffected — $(…) still captures that
# process's own stdout.
exec 3>&1 1>&2

log() { echo "$@"; }
die() { echo "error: $*"; exit 1; }
emit() { echo "$1=$2" >&3; }

descriptor="$REPO_ROOT/$kit/$kit.yaml"
[ -f "$descriptor" ] || descriptor="$REPO_ROOT/$kit/$kit.yml"
[ -f "$descriptor" ] ||
  die "no kit '$kit' at the repo root (expected $kit/$kit.yaml)"

# The reference is COMPOSED from the kit directory, never read from the
# descriptor. There is nothing in a v3 descriptor that names where it should be
# published, and that is the right way round: the name is this pipeline's to
# choose, so a kit cannot aim the push at a repository this repository does not
# own. (v2 had to read `sandbox.image` out of the spec, which is why it also
# needed a check-image-ref.sh to police what it read.)
ref="${REGISTRY}/${IMAGE_NAMESPACE}/${IMAGE_NAME_PREFIX}${kit}"

# One resolver for the publish tag and for the release-tag check, so a released
# version and a published one cannot mean different things. See kit-version.sh
# for the rule and why it has four sources.
version=$("$SCRIPT_DIR/kit-version.sh" "$kit") ||
  die "cannot resolve a version for '$kit' — see above"

if [ "$MOVE_LATEST" = "true" ]; then
  tags="${version},${IMAGE_TAG_LATEST}"
else
  tags="${version}"
fi

log "kit        : ${kit}"
log "descriptor : ${descriptor#"$REPO_ROOT"/}"
log "version    : ${version}"
log "reference  : ${ref}"
log "tags       : ${tags}"
log "platforms  : ${PLATFORMS}"

# Both tags are arguments to ONE build. Two builds — or one build and a later
# retag — are how `latest` and `<version>` come to describe different bytes:
# these kits install from floating channels onto floating bases, so two builds
# minutes apart legitimately differ. One invocation makes that impossible
# rather than unlikely.
#
# There is no immutable <date>-<sha> tag. v2 published one because its rolling
# tag had to point somewhere stable and the content was not a function of the
# commit. v3 tags by the kit's own version instead, which says something a
# consumer can act on ("this is Claude Code 2.1.267") where a date-and-sha said
# only when it was built. The trade is deliberate and worth stating plainly:
# <version> is NOT immutable here. A nightly rebuild re-pushes the same version
# tag with a fresh base and a fresh install, which is the point of the nightly
# — pin a digest, not a version, if you need the bytes to hold still.
args=(
  buildx build
  "$REPO_ROOT/$kit"
  -f "$descriptor"
  --platform "$PLATFORMS"
  --provenance=true
  --sbom="generator=${SBOM_GENERATOR}"
  -t "${ref}:${version}"
)

# MOVE_LATEST=false is for the release path, and the reason is a footgun rather
# than a preference. A `<kit>/vX.Y.Z` tag can sit on a commit that is not main's
# tip; publishing the rolling tag from it would move `latest` BACKWARD onto an
# older build, silently, for everyone who installs the kit without pinning.
# The rolling tag follows main, which is the branch every kit here is tested
# against on every PR. A release is a named point someone chose to pin, which
# is the opposite of rolling.
if [ "$MOVE_LATEST" = "true" ]; then
  args+=(-t "${ref}:${IMAGE_TAG_LATEST}")
fi

# `if`, not `[ … ] && args+=(…)`: the && form's exit status is the failed test's
# when the variable is empty, which reads as though it should abort under
# `set -e` even though it does not. Spelling it out removes the question.
if [ -n "$BUILDER" ]; then args+=(--builder "$BUILDER"); fi
if [ -n "$CACHE_FROM" ]; then args+=(--cache-from "$CACHE_FROM"); fi
if [ -n "$CACHE_TO" ]; then args+=(--cache-to "$CACHE_TO"); fi
if [ -n "$NO_CACHE" ]; then args+=(--no-cache); fi

# A dry run BUILDS. It is the whole value of the pull-request run: the frontend
# validates the descriptor during the build and the recipe has to actually
# work, so a dry run that stopped at "resolved the tag" would let a kit that
# cannot build report a green publish job and fail on merge — which is the
# failure this job exists to catch. `type=cacheonly` is what makes that
# affordable: the image is built and then discarded rather than exported, so
# nothing is written to a registry and nothing is loaded locally.
if [ -n "$DRY_RUN" ]; then
  args+=(--output type=cacheonly)
else
  args+=(--push)
fi

log ""
log "==> docker ${args[*]}"
log ""

docker "${args[@]}"

emit ref "$ref"
emit version "$version"
emit tags "$tags"
emit pushed "$([ -n "$DRY_RUN" ] && echo false || echo true)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## ${kit}"
    echo ""
    if [ -n "$DRY_RUN" ]; then
      echo "**Dry run — built, nothing published.**"
      echo ""
      echo "Would have published \`${ref}\`:"
    elif [ "$MOVE_LATEST" = "true" ]; then
      echo "Published — both tags resolve to the same digest:"
    else
      echo "Published:"
    fi
    echo ""
    echo "- \`${ref}:${version}\` — the kit's own version"
    if [ "$MOVE_LATEST" = "true" ]; then
      echo "- \`${ref}:${IMAGE_TAG_LATEST}\` — rolling"
    else
      echo ""
      echo "_The rolling \`${IMAGE_TAG_LATEST}\` tag was not moved — it follows main, not releases._"
    fi
    echo ""
    echo "Platforms: \`${PLATFORMS}\`. Provenance and SBOM attached."
  } >> "$GITHUB_STEP_SUMMARY"
fi

log ""
log "done"
