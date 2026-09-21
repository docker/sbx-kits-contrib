#!/usr/bin/env bash
# Validate a kit release tag and resolve what it names.
#
# Usage:
#   scripts/check-release-tag.sh <tag>
#
#   scripts/check-release-tag.sh github-ssh/v1.0.0
#
# The invariant: a release tag is `<kit>/vX.Y.Z`, it names a kit that exists,
# and the version that kit PUBLISHES UNDER is the same X.Y.Z.
#
# Why the two have to agree: the tag is not what gets published. The publisher
# resolves the version from the descriptor (see kit-version.sh) and tags the
# image with that, so a `claude/v9.9.9` tag on a descriptor resolving to 2.1.267
# publishes `sbx-kit-claude:2.1.267` — a release announcing a version that
# exists nowhere but in git. This check is what makes the git tag and the
# published tag the same statement.
#
# What changed from v2: this used to compare the tag against a LITERAL
# `version:` read out of spec.yaml with its own inline awk. In v3 that field is
# usually `${{ kit.args.version }}`, so a literal read returns the reference
# itself and every release fails. It now asks kit-version.sh — the same
# resolver publish-kit.sh tags with — precisely so the two cannot drift. That
# is also why the inline awk is gone: a second implementation of the rule is a
# second thing to get wrong, and this is the one place where getting it wrong
# is silent.
#
# On success, prints `kit=` and `version=` on stdout, one per line, so CI can
# redirect straight into $GITHUB_OUTPUT. Everything diagnostic goes to stderr,
# which keeps that redirect safe.
#
# Exit codes: 0 valid · 1 invalid tag or disagreeing descriptor · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <tag>          # e.g. github-ssh/v1.0.0" >&2
  exit 2
fi

tag=$1

# The KEY=VALUE stream CI redirects into $GITHUB_OUTPUT moves to fd 3, and stdout
# is rerouted to stderr, so nothing added later — an awk that prints, a helper
# that echoes — can put a malformed line in $GITHUB_OUTPUT and fail the step
# with "Invalid format". This matters more than it did: the script now shells
# out to kit-version.sh, which prints diagnostics of its own.
exec 3>&1 1>&2

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# `<kit>/vX.Y.Z`. The kit half is matched against the charset a kit directory
# may use, so a tag cannot name a directory a kit could never be.
case "$tag" in
  */*/*)
    echo "error: '${tag}' has more than one '/' — expected <kit>/vX.Y.Z"
    exit 1
    ;;
  */*) ;;
  *)
    echo "error: '${tag}' is not a release tag — expected <kit>/vX.Y.Z"
    exit 1
    ;;
esac

kit=${tag%%/*}
version=${tag##*/}

if ! printf '%s' "$kit" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$'; then
  echo "error: '${kit}' is not a valid kit name"
  exit 1
fi

# Three numeric components, `v`-prefixed. Deliberately stricter than semver:
# pre-release and build metadata are refused rather than half-supported, since
# nothing downstream — the tag, the image tag, the check below — has anywhere
# to put them.
if ! printf '%s' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: '${version}' must be vX.Y.Z (no pre-release or build suffix)"
  exit 1
fi

descriptor="$REPO_ROOT/$kit/$kit.yaml"
[ -f "$descriptor" ] || descriptor="$REPO_ROOT/$kit/$kit.yml"
if [ ! -f "$descriptor" ]; then
  echo "error: tag names kit '${kit}', which has no ${kit}/${kit}.yaml at the repo root"
  exit 1
fi

# kit-version.sh explains its own failures — a missing default, an expression it
# cannot resolve, a kit declaring no version at all — in more detail than this
# script could, and it has already printed them to stderr by the time this runs.
if ! declared=$("$SCRIPT_DIR/kit-version.sh" "$kit"); then
  echo ""
  echo "error: ${kit} has no resolvable version, so ${tag} cannot be released"
  exit 1
fi

want=${version#v}

if [ "$declared" != "$want" ]; then
  # Where the number came from is most of the fix. "Bump the version" is
  # useless advice when the field holds `${{ kit.args.version }}` and the
  # number actually lives in an arg default three lines further down.
  source=$("$SCRIPT_DIR/kit-version.sh" --all | awk -F'\t' -v k="$kit" '$1==k{print $3}')
  case "$source" in
    literal)  where="the top-level 'version:' in ${kit}/${kit}.yaml" ;;
    arg:*)    where="args.${source#arg:}.default in ${kit}/${kit}.yaml — the top-level 'version:' only references it" ;;
    provides) where="the pinned entry in provides: in ${kit}/${kit}.yaml — the kit declares no 'version:' of its own" ;;
    *)        where="${kit}/${kit}.yaml" ;;
  esac

  cat <<EOF

error: ${kit} does not publish the version this tag names

  tag            : ${tag}
  kit publishes  : ${declared}
  tag expects    : ${want}

The published tag comes from the descriptor, not from this git tag, so
releasing this would publish ${kit}:${declared} under a ${tag} announcement.

The number lives in ${where}.

Change it and re-tag, or tag the version the kit already publishes:

  git tag ${kit}/v${declared}
EOF
  exit 1
fi

echo "ok: ${tag} -> ${kit} ${version} (the kit publishes ${declared})"

echo "kit=${kit}" >&3
echo "version=${version}" >&3
