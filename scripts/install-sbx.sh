#!/usr/bin/env bash
# Install the sbx CLI from docker/sbx-releases.
#
# Usage:
#   scripts/install-sbx.sh [version]
#
#   scripts/install-sbx.sh              # latest release
#   scripts/install-sbx.sh v0.12.3      # a specific tag
#
# Environment:
#   PREFIX        install root, default $HOME/.docker/sbx
#   GITHUB_TOKEN  required — sbx-releases is private, so both the API lookup
#                 and the asset download need it
#
# Prints the directory to add to PATH on stdout; progress goes to stderr. In CI:
#
#   ./scripts/install-sbx.sh >> "$GITHUB_PATH"
#
# Exit codes: 0 installed · 1 failed · 2 usage error.

set -euo pipefail

if [ $# -gt 1 ]; then
  echo "usage: $0 [version]" >&2
  exit 2
fi

version=${1:-}
PREFIX=${PREFIX:-$HOME/.docker/sbx}

# The PATH directory CI redirects into $GITHUB_PATH moves to fd 3, and stdout is
# rerouted to stderr. install.sh prints its own progress on stdout, which would
# otherwise be appended to $GITHUB_PATH as bogus entries — silently, since that
# file takes one path per line and does not validate them.
exec 3>&1 1>&2

log() { echo "$@"; }
die() { echo "error: $*"; exit 1; }

[ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN is required (docker/sbx-releases is private)"

case "$(uname -s)" in
  Linux) asset="DockerSandboxes-linux.tar.gz" ;;
  *) die "$(uname -s) is not supported by this script; install sbx by hand" ;;
esac

if [ -z "$version" ]; then
  log "==> resolving the latest release"
  version=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    https://api.github.com/repos/docker/sbx-releases/releases/latest | jq -r .tag_name)
  [ -n "$version" ] && [ "$version" != "null" ] || die "could not resolve the latest release"
fi
log "    version ${version}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "==> downloading ${asset}"
curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://github.com/docker/sbx-releases/releases/download/${version}/${asset}" \
  -o "${tmp}/${asset}"
tar xzf "${tmp}/${asset}" -C "$tmp"

# The installer runs under sudo, so create the parent unprivileged first: if
# $PREFIX's parent is absent it would be created root-owned, and on a CI runner
# that parent is usually ~/.docker — which a later `docker login` then cannot
# write config.json into. That file is the only credential `sbx kit push` and
# `oras` read, so the failure would land far from its cause.
mkdir -p "$(dirname "$PREFIX")"

log "==> installing into ${PREFIX}"
if [ "$(id -u)" -eq 0 ]; then
  PREFIX="$PREFIX" "${tmp}/docker-sbx/install.sh"
else
  sudo PREFIX="$PREFIX" "${tmp}/docker-sbx/install.sh"
fi

log "==> installed: $("${PREFIX}/bin/sbx" version 2>/dev/null | head -1 || echo "sbx (version unavailable)")"

echo "${PREFIX}/bin" >&3
