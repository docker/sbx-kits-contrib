#!/usr/bin/env bash
# Read a kit's Hub-facing metadata out of its spec.yaml.
#
# Usage:
#   scripts/kit-meta.sh <kit>
#
#   scripts/kit-meta.sh kiro
#
# Emits, one per line, for redirecting into $GITHUB_OUTPUT:
#
#   title=                    displayName, falling back to name
#   kit-repository=           <namespace>/<kit>-kit — the artifact's Hub repo
#   image-repository=         sandbox.image with registry and tag stripped
#   short-description=        description, capped at Hub's 100 characters
#   image-short-description=  written for the BASE IMAGE repo, which is a
#                             separate Hub repository and would otherwise carry
#                             text describing the kit instead
#
# Why a script rather than two lines of YAML: this is the third place that has
# had to parse a top-level scalar out of spec.yaml (see check-release-tag.sh),
# and the parsing has a subtlety worth writing once — a value may be quoted, may
# carry a trailing comment, and only a TOP-LEVEL key is the kit's own.
#
# Environment:
#   IMAGE_NAMESPACE   default sbx — used to compose the kit artifact's repository
#
# Exit codes: 0 read · 1 no such kit · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <kit>" >&2
  exit 2
fi

kit=$1
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-sbx}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# KEY=VALUE goes to fd 3; stdout is rerouted to stderr so nothing added later
# can pollute the stream CI reads.
exec 3>&1 1>&2

spec="$REPO_ROOT/$kit/spec.yaml"
[ -f "$spec" ] || spec="$REPO_ROOT/$kit/spec.yml"
[ -f "$spec" ] || { echo "error: no spec.yaml for kit '$kit'"; exit 1; }

# Top-level scalar only: an indented `description:` belongs to a setup command
# or a credential, not to the kit. kiro's spec has three of those, so anchoring
# to column zero is what makes this correct rather than merely working.
scalar() {
  awk -v key="$1" '
    /^[[:space:]]*#/ { next }
    index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$spec"
}

title=$(scalar displayName)
[ -n "$title" ] || title=$(scalar name)

description=$(scalar description)

# Hub caps the short description at 100 characters and rejects longer ones, so
# cap here rather than discovering it as an API error mid-publish.
cap() {
  if [ ${#1} -gt 100 ]; then
    # Announced, not silent: a truncated description is a spec worth shortening
    # by hand, and the cut is invisible in the emitted value itself.
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

# `<kit>-image` and `<kit>-kit` are two Hub repositories holding different
# things: the image a sandbox boots from, and the kit artifact that references
# it. Giving both the kit's description would leave a browser of the image repo
# with no idea which of the two they are looking at.
image_description=$(cap "Base image for the ${title} kit for Docker Sandboxes")
description=$(cap "$description")

# The Hub API addresses repositories as <namespace>/<name>. The kit artifact's
# is composed (the same rule publish-artifact.sh enforces); the image's is READ from
# the spec, because that name is the spec's to choose and is not derivable.
image_repository=$(awk '
  /^sandbox:/      { in_sandbox = 1; next }
  /^[^[:space:]#]/ { in_sandbox = 0 }
  in_sandbox && $1 == "image:" {
    gsub(/^[[:space:]]*image:[[:space:]]*/, "")
    gsub(/^["'"'"']|["'"'"']$/, "")
    print; exit
  }
' "$spec")
image_repository=${image_repository%%@*}
image_repository=${image_repository%:*}
image_repository=${image_repository#*/}

# Only the KEY=VALUE stream is printed. Echoing a prose copy to stderr as well
# would double every line on a terminal, where both streams land together — and
# `key=value` reads perfectly well on its own. Diagnostics here are limited to
# things the values do not say, like the truncation notice above.
echo "title=${title}" >&3
echo "kit-repository=${IMAGE_NAMESPACE}/${kit}-kit" >&3
echo "short-description=${description}" >&3
echo "image-short-description=${image_description}" >&3

# Omitted rather than emitted empty for a kit that builds no image, so a caller
# can branch on its presence. An `if` rather than `[ … ] && echo`, which does not
# abort under set -e when the test fails and reads as though it might.
if [ -n "$image_repository" ]; then
  echo "image-repository=${image_repository}" >&3
fi
