#!/usr/bin/env bash
# Install the sbx CLI from docker/sbx-releases.
#
# Usage:
#   scripts/install-sbx.sh [channel|version]
#   scripts/install-sbx.sh --resolve [channel|version]
#
#   scripts/install-sbx.sh              # latest release candidate (the default)
#   scripts/install-sbx.sh rc           # ... the same, spelled out
#   scripts/install-sbx.sh nightly      # the rolling nightly build
#   scripts/install-sbx.sh release      # the last STABLE release — see the warning
#   scripts/install-sbx.sh v0.12.3      # a specific tag
#   scripts/install-sbx.sh --resolve rc # print the tag a channel resolves to, install nothing
#
# WHY THE DEFAULT IS A RELEASE CANDIDATE AND NOT THE STABLE RELEASE
#
# Every kit in this repository is a v3 kit, and running one in source form
# (`sbx run ./<kit>`) needs the kit builder that resolves and builds a v3
# descriptor. The stable line predates that, so it cannot load these kits at all
# — pointing this script at `release` gets a CLI that fails on every kit here,
# which looks like a broken kit rather than a too-old CLI. So the default is the
# earliest channel that works, and asking for `release` prints a warning saying
# so rather than silently handing back a CLI that cannot do the job.
#
# `release` is deliberately still reachable: it is the channel to install the day
# stable gains kit v3 support, to confirm it, and the day it does, that becomes
# the sensible default again.
#
# CHANNEL RESOLUTION LIVES HERE, AND ONLY HERE
#
# .github/workflows/e2e.yml has to know the resolved version before it downloads
# anything (it downloads the tarball once and shares it with the kit matrix as an
# artifact, rather than having every matrix leg re-download a private release
# asset). It gets that version from `--resolve` instead of carrying its own copy
# of the case statement below, so there is one definition of what "rc" means.
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
# With --resolve, prints the resolved tag on stdout instead and installs nothing.
#
# Exit codes: 0 installed (or resolved) · 1 failed · 2 usage error.

set -euo pipefail

resolve_only=
if [ "${1:-}" = "--resolve" ]; then
  resolve_only=1
  shift
fi

if [ $# -gt 1 ]; then
  echo "usage: $0 [--resolve] [channel|version]" >&2
  exit 2
fi

# `rc` rather than `release`: see the block comment above.
channel=${1:-rc}
PREFIX=${PREFIX:-$HOME/.docker/sbx}

# The PATH directory CI redirects into $GITHUB_PATH moves to fd 3, and stdout is
# rerouted to stderr. install.sh prints its own progress on stdout, which would
# otherwise be appended to $GITHUB_PATH as bogus entries — silently, since that
# file takes one path per line and does not validate them. --resolve prints its
# version to the same fd 3, for the same reason: everything this script says about
# what it is doing has to stay out of the value a caller is capturing.
exec 3>&1 1>&2

log() { echo "$@"; }
die() { echo "error: $*"; exit 1; }

[ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN is required (docker/sbx-releases is private)"

gh_api() {
  curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/docker/sbx-releases/$1"
}

# Resolve the channel to a release tag. Anything that is not a known channel name
# is taken as a tag verbatim, so a pinned `v0.12.3` still works and a typo fails
# at the download with a 404 naming what was asked for.
case "$channel" in
  nightly)
    # The nightly build publishes under a rolling tag literally named `nightly`,
    # so there is nothing to look up.
    version=nightly
    ;;
  rc)
    log "==> resolving the latest release candidate"
    # /releases (not /releases/latest, which skips prereleases by definition),
    # newest first, first tag ending in -rcN.
    version=$(gh_api releases | jq -er '[.[] | select(.tag_name | test("-rc[0-9]+$"))][0].tag_name') \
      || die "could not resolve the latest release candidate"
    ;;
  release)
    log "==> resolving the latest stable release"
    version=$(gh_api releases/latest | jq -er .tag_name) \
      || die "could not resolve the latest stable release"
    log ""
    log "WARNING: the stable line predates kit v3 and cannot load the kits in this"
    log "         repository. Use the default (rc) or 'nightly' to run or test a kit."
    log ""
    ;;
  *)
    version=$channel
    ;;
esac

[ -n "$version" ] && [ "$version" != "null" ] || die "could not resolve a version for channel '${channel}'"
log "    version ${version}"

if [ -n "$resolve_only" ]; then
  echo "$version" >&3
  exit 0
fi

case "$(uname -s)" in
  Linux) asset="DockerSandboxes-linux.tar.gz" ;;
  *) die "$(uname -s) is not supported by this script; install sbx by hand" ;;
esac

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
