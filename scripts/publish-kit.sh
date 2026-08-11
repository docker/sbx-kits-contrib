#!/usr/bin/env bash
# Publish one kit as an OCI artifact to <registry>/<namespace>/<kit>-kit.
#
# Usage:
#   scripts/publish-kit.sh <kit> <tag>
#
#   DRY_RUN=1 scripts/publish-kit.sh kiro v1.0.0        # print the plan, touch nothing
#   MOVE_LATEST=true scripts/publish-kit.sh kiro abc-20260811
#
# Environment:
#   REGISTRY          default docker.io
#   IMAGE_NAMESPACE   default sbx
#   IMAGE_TAG_LATEST  default latest        — the rolling tag MOVE_LATEST moves
#   MOVE_LATEST       default false         — also re-point the rolling tag
#   DRY_RUN           set to any value      — resolve and report, publish nothing
#
# Emits `ref=`, `digest=`, `pushed=` and `reused=` on stdout, one per line, so CI
# can redirect into $GITHUB_OUTPUT. Everything human goes to stderr, which keeps
# that redirect safe. When GITHUB_STEP_SUMMARY is set, a summary is appended
# there too.
#
# Exit codes: 0 published (or dry run) · 1 refused or failed · 2 usage error.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <kit> <tag>" >&2
  exit 2
fi

kit=$1
tag=$2

REGISTRY=${REGISTRY:-docker.io}
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-sbx}
IMAGE_TAG_LATEST=${IMAGE_TAG_LATEST:-latest}
MOVE_LATEST=${MOVE_LATEST:-false}
DRY_RUN=${DRY_RUN:-}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

log() { echo "$@" >&2; }
die() { echo "error: $*" >&2; exit 1; }

[ -d "$REPO_ROOT/$kit" ] || die "no kit directory '$kit' at the repo root"
[ -f "$REPO_ROOT/$kit/spec.yaml" ] || [ -f "$REPO_ROOT/$kit/spec.yml" ] ||
  die "'$kit' has no spec.yaml"

# The reference is COMPOSED from the kit directory, never taken from the spec or
# an argument. `sbx kit push` uses whatever reference it is handed verbatim — it
# derives nothing from the kit name and validates nothing against it — so a
# wrong value would push a kit manifest over an unrelated tag in this namespace,
# the kit's own base image included.
ref="${REGISTRY}/${IMAGE_NAMESPACE}/${kit}-kit"

log "kit         : ${kit}"
log "reference   : ${ref}:${tag}"
log "rolling tag : $([ "$MOVE_LATEST" = "true" ] && echo "${ref}:${IMAGE_TAG_LATEST}" || echo "(not moved)")"

emit() { echo "$1=$2"; }

summarise() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "## ${kit} (kit artifact)"
    echo ""
    printf '%s\n' "$1"
  } >> "$GITHUB_STEP_SUMMARY"
}

if [ -n "$DRY_RUN" ]; then
  log ""
  log "DRY RUN — nothing is published. Would:"
  log "  1. sbx kit validate ${kit}"
  log "  2. check ${ref}:${tag} does not already exist"
  log "  3. sbx kit push ${kit} ${ref}:${tag} --sign"
  [ "$MOVE_LATEST" = "true" ] &&
    log "  4. oras tag ${ref}@<digest> ${IMAGE_TAG_LATEST}"
  emit ref "$ref"
  emit pushed false
  emit reused false
  summarise "**Dry run — nothing published.** Would have published \`${ref}:${tag}\`."
  exit 0
fi

for bin in sbx oras jq; do
  command -v "$bin" >/dev/null || die "$bin is not on PATH (scripts/install-sbx.sh installs sbx)"
done

log ""
log "==> validating"
sbx kit validate "$REPO_ROOT/$kit"

# Tags are immutable by convention; the registry does not enforce that unless
# Hub tag-immutability is on. What a collision means depends on the caller:
#
#   MOVE_LATEST=false (a release) — a version is being re-cut over a published
#     one. Always an error; the fix is a new version.
#   MOVE_LATEST=true (continuous) — the tag is <sha>-<date>, so a collision just
#     means this commit was already published today, i.e. a re-run. Reuse it: a
#     re-run is the only way back when the push landed and a later step did not,
#     and failing here would strand the rolling tag on the previous artifact.
#
# Probed with oras, not `docker manifest inspect`: the kit is an OCI manifest
# with a custom artifactType and a non-image config, which image-oriented
# tooling may reject outright — and a rejection would be indistinguishable from
# "absent", waving through the overwrite this check exists to prevent.
log "==> checking whether ${ref}:${tag} already exists"
existing_err=$(mktemp)
trap 'rm -f "$existing_err"' EXIT
reused=false
digest=""

if existing=$(oras manifest fetch --descriptor "${ref}:${tag}" 2>"$existing_err"); then
  digest=$(printf '%s' "$existing" | jq -r .digest)
  if [ "$MOVE_LATEST" = "true" ]; then
    log "    already exists (${digest}) — re-run, reusing it"
    reused=true
  else
    die "${ref}:${tag} already exists (${digest}). Published versions are immutable — cut a new version rather than re-tagging this one."
  fi
else
  # "Not there" and "could not tell" are different answers. Treating an auth or
  # transport failure as absent is how an immutable tag gets overwritten.
  if grep -qiE 'not found|manifest unknown|name unknown|404' "$existing_err"; then
    log "    not published yet"
  else
    log "    could not determine whether it exists:"
    cat "$existing_err" >&2
    exit 1
  fi
fi

if [ "$reused" = "false" ]; then
  log "==> pushing (signed)"
  # --sign is keyless: in CI the Sigstore identity comes from the ambient
  # GitHub OIDC token, which is why the calling job needs id-token: write.
  # Every push also attaches a SLSA provenance referrer recording the kit's
  # content digests, its declared sandbox image, and the source commit.
  sbx kit push "$REPO_ROOT/$kit" "${ref}:${tag}" --sign

  # The push does not echo the digest, and re-reading the tag later would let a
  # racing push swap the manifest we then advertise as the rolling tag.
  digest=$(oras manifest fetch --descriptor "${ref}:${tag}" | jq -r .digest)
  # An `if`, not `[ -n "$d" ] && [ "$d" != null ]`: set -e does not fire when
  # the FIRST test of an && list fails, so that form falls through with an empty
  # digest and blows up later on `oras tag "<ref>@"`.
  if [ -z "$digest" ] || [ "$digest" = "null" ]; then
    die "pushed ${ref}:${tag} but could not read back its digest"
  fi
  log "    pushed ${digest}"
fi

if [ "$MOVE_LATEST" = "true" ]; then
  # Retag by digest rather than pushing a second time. A second push re-packs
  # the kit, and oras.PackManifest stamps org.opencontainers.image.created, so
  # the second manifest almost always digests differently — and each digest
  # carries its OWN provenance and signature, so the two tags would advertise
  # different attestations for one source. "Almost always" is the problem: that
  # annotation has one-second resolution, so two pushes inside the same second
  # produce identical manifests and the divergence silently does not happen.
  #
  # Needs PULL as well as push: the manifest is fetched before being re-PUT.
  # With a push-only credential this fails AFTER the immutable tag is published.
  log "==> re-pointing ${IMAGE_TAG_LATEST} at ${digest}"
  oras tag "${ref}@${digest}" "${IMAGE_TAG_LATEST}"
fi

emit ref "$ref"
emit digest "$digest"
emit pushed "$([ "$reused" = "true" ] && echo false || echo true)"
emit reused "$reused"

{
  echo "Published \`${digest}\`:"
  echo ""
  echo "- \`${ref}:${tag}\`"
  [ "$MOVE_LATEST" = "true" ] &&
    echo "- \`${ref}:${IMAGE_TAG_LATEST}\` — rolling, re-pointed at the same digest"
  echo ""
  if [ "$reused" = "true" ]; then
    echo "_Tag already existed — reused rather than re-pushed._"
  else
    echo "Signed keyless (Sigstore), with a SLSA provenance referrer."
  fi
} > /tmp/publish-kit-summary.md
summarise "$(cat /tmp/publish-kit-summary.md)"
log ""
log "done"
