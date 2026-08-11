#!/usr/bin/env bash
# Validate a kit release tag and resolve what it names.
#
# Usage:
#   scripts/check-release-tag.sh <tag>
#
#   scripts/check-release-tag.sh kiro/v1.0.0
#
# The invariant: a release tag is `<kit>/vX.Y.Z`, it names a kit that exists,
# and the kit's `spec.yaml` declares the same version.
#
# Why the spec has to agree: `manifest.version` becomes the OCI annotation
# vnd.docker.sandbox.kit.version at pack time, which is what distribution
# tooling reads without pulling layers. The field is OPTIONAL, so without this
# check `kiro/v1.0.0` would happily publish an artifact annotated 0.9.0 — or
# annotated nothing at all — leaving the git tag as the only place the version
# exists. Nothing downstream would notice.
#
# On success, prints `kit=` and `version=` on stdout, one per line, so CI can
# redirect straight into $GITHUB_OUTPUT. Everything diagnostic goes to stderr,
# which keeps that redirect safe.
#
# Exit codes: 0 valid · 1 invalid tag or mismatched spec · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <tag>          # e.g. kiro/v1.0.0" >&2
  exit 2
fi

tag=$1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# `<kit>/vX.Y.Z`. The kit half is matched against the same charset spec.yaml
# allows for `name`, so a tag cannot name a directory a kit could never be.
case "$tag" in
  */*/*)
    echo >&2 "error: '${tag}' has more than one '/' — expected <kit>/vX.Y.Z"
    exit 1
    ;;
  */*) ;;
  *)
    echo >&2 "error: '${tag}' is not a release tag — expected <kit>/vX.Y.Z"
    exit 1
    ;;
esac

kit=${tag%%/*}
version=${tag##*/}

if ! printf '%s' "$kit" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$'; then
  echo >&2 "error: '${kit}' is not a valid kit name"
  exit 1
fi

# Three numeric components, `v`-prefixed. Deliberately stricter than semver:
# pre-release and build metadata are refused rather than half-supported, since
# nothing downstream — the tag, the annotation, the check below — has anywhere
# to put them.
if ! printf '%s' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo >&2 "error: '${version}' must be vX.Y.Z (no pre-release or build suffix)"
  exit 1
fi

spec="$REPO_ROOT/$kit/spec.yaml"
[ -f "$spec" ] || spec="$REPO_ROOT/$kit/spec.yml"
if [ ! -f "$spec" ]; then
  echo >&2 "error: tag names kit '${kit}', which has no spec.yaml at the repo root"
  exit 1
fi

# Top-level `version:` only — anything indented belongs to another block
# (sandbox.build.args, a credential, …) and is not the kit's version.
declared=$(awk '
  /^[[:space:]]*#/ { next }
  /^version:/ {
    sub(/^version:[[:space:]]*/, "")
    gsub(/^["'"'"']|["'"'"']$/, "")
    sub(/[[:space:]]+#.*$/, "")
    print
    exit
  }
' "$spec")

want=${version#v}

if [ -z "$declared" ]; then
  cat >&2 <<EOF

error: ${kit}/spec.yaml declares no top-level 'version:'

  tag       : ${tag}
  expected  : version: ${want}

The version is published as an OCI annotation, so a kit released without one
carries no version anywhere a consumer can read it.
EOF
  exit 1
fi

if [ "$declared" != "$want" ]; then
  cat >&2 <<EOF

error: ${kit}/spec.yaml version does not match the tag

  tag       : ${tag}
  spec says : ${declared}
  expected  : ${want}

Bump the spec and re-tag, or tag the version the spec already declares.
EOF
  exit 1
fi

echo >&2 "ok: ${tag} -> ${kit} ${version} (spec declares ${declared})"

echo "kit=${kit}"
echo "version=${version}"
