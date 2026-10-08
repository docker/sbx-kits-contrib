#!/usr/bin/env bash
# Refuse a kit name that would publish over something else.
#
# Usage:
#   scripts/check-kit-name.sh <name>
#
#   scripts/check-kit-name.sh claude        # ok
#   scripts/check-kit-name.sh claude-kit    # refused
#
# A v3 kit publishes as <registry>/<namespace>/<name>, composed from the
# directory and nothing else. `-kit` and `-image` are the v2 scheme's two names
# for one kit (`claude-kit` carried the spec, `claude-image` the base), they are
# still published from the frozen v2 branch, and both land in the same `sbx`
# namespace this one publishes to. So a kit directory named `foo-kit` resolves
# to `sbx/foo-kit` and overwrites the v2 artifact for a kit called `foo` — a
# silent cross-generation overwrite, in the one place nothing downstream would
# notice.
#
# THE RULE LIVES HERE, in one file, because it has to hold at four different
# moments and the first draft only enforced it at one. Discovery lists kits;
# publish-kit.sh and kit-meta.sh COMPOSE the reference from an argument; and
# check-release-tag.sh takes a kit name out of a git tag a human pushed. A guard
# in the lister does nothing about `scripts/publish-kit.sh claude-kit` typed by
# hand, or about a `claude-kit/v1.0.0` tag — the two paths that are not fed by
# discovery at all.
#
# Exit codes: 0 usable · 1 reserved · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <name>" >&2
  exit 2
fi

name=$1

case "$name" in
  *-kit | *-image)
    cat >&2 <<EOF
error: kit name '${name}' uses a reserved suffix

  '-kit' and '-image' name v2 artifacts in the same Hub namespace this
  publishes to, so '${name}' would resolve to a repository the v2 branch
  owns and overwrite it.

  Rename the kit. The suffix carries no meaning in v3: a kit is one image
  and its repository is just its name.
EOF
    exit 1
    ;;
esac

exit 0
