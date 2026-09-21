#!/usr/bin/env bash
# Read a kit's Hub-facing metadata out of its v3 descriptor.
#
# Usage:
#   scripts/kit-meta.sh <kit>
#
#   scripts/kit-meta.sh claude
#
# Emits, one per line, for redirecting into $GITHUB_OUTPUT:
#
#   title=              displayName, falling back to the kit directory name
#   kit-repository=     <namespace>/sbx-kit-<kit> — the kit's Hub repo
#   short-description=  description, folded to one line and capped at Hub's
#                       100 characters
#
# WHAT IS NO LONGER EMITTED, and why that is safe. v2 gave every publishing kit
# TWO Hub repositories with two different descriptions: `<kit>-kit` for the
# artifact and `<kit>-image` for the image its sandbox booted from. This script
# emitted `image-repository=` and `image-short-description=` for the second one,
# reading the repository name out of the spec's `sandbox.image` because that
# name was the spec's to choose and was not derivable.
#
# A v3 kit is ONE image. There is no second repository, no `sandbox.image` to
# read, and nothing for a second description to describe. Both keys are dropped
# rather than emitted empty, which is exactly the shape hub-overview.yml already
# handles: its base-image steps are gated on `image-repository != ''`, so they
# skip on an absent key the same way they used to skip for a kit that built no
# image of its own. (They are doubly gated — the same workflow also requires a
# `Dockerfile`, and no kit has one any more.)
#
# Environment:
#   IMAGE_NAMESPACE     default docker      — the Hub org the kit publishes to
#   IMAGE_NAME_PREFIX   default sbx-kit-    — must match publish-kit.sh's
#
# Exit codes: 0 read · 1 no such kit · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <kit>" >&2
  exit 2
fi

kit=$1
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-docker}
IMAGE_NAME_PREFIX=${IMAGE_NAME_PREFIX:-sbx-kit-}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# KEY=VALUE goes to fd 3; stdout is rerouted to stderr so nothing added later
# can pollute the stream CI reads.
exec 3>&1 1>&2

descriptor="$REPO_ROOT/$kit/$kit.yaml"
[ -f "$descriptor" ] || descriptor="$REPO_ROOT/$kit/$kit.yml"
[ -f "$descriptor" ] || { echo "error: no kit '${kit}' at the repo root (expected ${kit}/${kit}.yaml)"; exit 1; }

# A top-level scalar, folded to one line.
#
# The fold is the part v2 did not need. Most v3 descriptions are written as
# `description: >-` folded block scalars over two or three indented lines,
# because the prose is long enough that one line would be unreadable in the
# file. Reading only the key's own line — which is what the v2 version of this
# script did — returns the literal string ">-" and publishes that as the Hub
# short description.
#
# Only a TOP-LEVEL key counts: several kits carry an indented `description:`
# on a build arg or a credential, and those describe a field, not the kit.
scalar() {
  awk -v key="$2" '
    # Column-zero key: either the one being looked for, or the one that ends
    # a block scalar already being collected.
    /^[^[:space:]#]/ {
      if (collecting) exit
      if (index($0, key ":") == 1) {
        value = $0
        sub("^" key ":[[:space:]]*", "", value)
        # Comment first, THEN quotes: stripping quotes first leaves the closing
        # one stranded on `displayName: "Claude Code"  # note`.
        sub(/[[:space:]]+#.*$/, "", value)
        gsub(/^["'"'"']|["'"'"']$/, "", value)
        # A block-scalar indicator (>, >-, |, |-, and their explicit-indent
        # forms) means the value is the indented lines that follow, not this
        # one. Anything else is the value itself.
        if (value ~ /^[>|][0-9]*[-+]?$/) { collecting = 1; value = ""; next }
        print value
        exit
      }
      next
    }
    collecting {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      # Folded and literal scalars are both flattened to one line: the only
      # consumer is Hub SHORT description, which is a single line by
      # definition. A blank line (a paragraph break in a folded scalar)
      # becomes the same single space as a line break.
      if (line == "") next
      out = (out == "" ? line : out " " line)
      next
    }
    END { if (collecting) print out }
  ' "$1"
}

title=$(scalar "$descriptor" displayName)
# v3 has no top-level `name:` — a kit is named by its directory, which is what
# discovery, the companion recipe's filename and the published reference are all
# keyed on. So the directory name is the fallback, not another field.
[ -n "$title" ] || title=$kit

description=$(scalar "$descriptor" description)

# Hub caps the short description at 100 characters and rejects longer ones, so
# cap here rather than discovering it as an API error mid-publish.
cap() {
  if [ ${#1} -gt 100 ]; then
    # Announced, not silent: a truncated description is a descriptor worth
    # shortening by hand, and the cut is invisible in the emitted value itself.
    #
    # `>&2` explicitly, even though the script reroutes stdout to stderr: this
    # function runs inside $(…), where fd 1 is the capture pipe rather than the
    # rerouted stream, so a bare echo would land in the returned VALUE.
    echo "notice: description exceeds Hub's 100-character limit and was cut: $1" >&2
    printf '%s...' "${1:0:97}"
  else
    printf '%s' "$1"
  fi
}

description=$(cap "$description")

# The Hub API addresses repositories as <namespace>/<name>, without the registry
# host an OCI reference carries. COMPOSED from the kit directory, matching the
# rule publish-kit.sh pushes by — in v3 nothing in the descriptor names where
# the kit is published, so there is no second source of truth to read and
# nothing that can drift.
echo "title=${title}" >&3
echo "kit-repository=${IMAGE_NAMESPACE}/${IMAGE_NAME_PREFIX}${kit}" >&3
echo "short-description=${description}" >&3
