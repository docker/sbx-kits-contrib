#!/usr/bin/env bash
# Sync one kit's logo to its Docker Hub repository.
#
# Usage:
#   scripts/hub-logo.sh <kit>
#
# The logo is the descriptor's top-level `iconUrl`, downloaded and uploaded to
# the kit's Hub repository. An `iconUrl` that is this repository's own Hub logo
# URL is skipped: it would only copy Hub onto Hub. No `iconUrl` is a skip, not
# an error. Logo files are deliberately not kept in this repository: they are
# third-party trademarks, and this tree is Apache-2.0.
#
# The upload is idempotent: the current logo is fetched through Hub's media
# alias and compared byte for byte; identical bytes upload nothing unless
# FORCE=true.
#
# Emits `source=`, `action=` and `detail=` on stdout, for $GITHUB_OUTPUT.
# Diagnostics go to stderr.
#
# Environment:
#   HUB_USERNAME, HUB_TOKEN   Hub login for the upload (not needed for DRY_RUN)
#   IMAGE_NAMESPACE           Hub namespace (default: sbx)
#   HUB_API                   Hub base URL (default: https://hub.docker.com);
#                             tests point it at a local server
#   DRY_RUN                   "true": resolve, validate and compare, never log in or upload
#   FORCE                     "true": upload even when the bytes already match
#   MAX_LOGO_BYTES            size cap (default: 1048576)
#   HUB_LOGO_FIELD            multipart field name of the media endpoint (default: file)
#   REPO_ROOT                 repository root (default: the parent of this script's directory)
#
# Exit codes: 0 synced/unchanged/skipped · 1 transport or Hub error · 2 usage or kit error.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-sbx}
HUB_API=${HUB_API:-https://hub.docker.com}
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
MAX_LOGO_BYTES=${MAX_LOGO_BYTES:-1048576}
HUB_LOGO_FIELD=${HUB_LOGO_FIELD:-file}

usage() { echo "usage: $0 <kit>" >&2; exit 2; }
[ $# -eq 1 ] || usage
kit=$1
case "$kit" in */*|.|..|"") echo "error: '$kit' is not a kit name" >&2; exit 2 ;; esac
[ -d "$REPO_ROOT/$kit" ] || { echo "error: no kit directory $REPO_ROOT/$kit" >&2; exit 2; }

exec 3>&1 1>&2
emit() { printf '%s=%s\n' "$1" "$2" >&3; }
log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit "${2:-1}"; }

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

repo="${IMAGE_NAMESPACE}/${kit}"
alias_url="${HUB_API}/api/media/repos_logo/v1/${IMAGE_NAMESPACE}%2F${kit}"

# --- 1. the source: iconUrl --------------------------------------------------

descriptor_icon_url() {
  local d="$REPO_ROOT/$1/$1.yaml"
  [ -f "$d" ] || d="$REPO_ROOT/$1/$1.yml"
  [ -f "$d" ] || return 0
  awk '
    /^[[:space:]]*#/ { next }
    index($0, "iconUrl:") == 1 {
      sub(/^iconUrl:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$d"
}

source_kind=""; source_detail=""; logo="$workdir/logo"
icon=$(descriptor_icon_url "$kit")
if [ -z "$icon" ]; then
  log "$kit: no iconUrl in the descriptor; skipping"
  emit source none; emit action skipped; emit detail "no iconUrl"
  exit 0
fi
if [ "$icon" = "$alias_url" ] || [ "$icon" = "${alias_url}?type=logo" ] \
   || [ "$icon" = "https://hub.docker.com/api/media/repos_logo/v1/${IMAGE_NAMESPACE}%2F${kit}" ]; then
  log "$kit: iconUrl is this repository's own Hub logo; nothing to mirror"
  emit source none; emit action skipped; emit detail "iconUrl points at ${repo}'s own Hub logo"
  exit 0
fi
curl --fail --silent --show-error --location --max-time 30 --output "$logo" "$icon" \
  || die "could not download iconUrl $icon"
source_kind="iconUrl"; source_detail="$icon"

# --- 2. validate what we are about to upload --------------------------------

size=$(wc -c <"$logo" | tr -d ' ')
[ "$size" -gt 0 ] || die "$source_detail is empty" 2
[ "$size" -le "$MAX_LOGO_BYTES" ] || die "$source_detail is ${size} bytes, over the ${MAX_LOGO_BYTES}-byte cap" 2

magic=$(head -c 8 "$logo" | od -An -tx1 | tr -d ' \n')
head_text=$(head -c 512 "$logo" | tr -d '\0')
if [ "${magic:0:16}" = "89504e470d0a1a0a" ]; then
  mime=image/png; ext=png
elif printf '%s' "$head_text" | grep -qi '<svg'; then
  mime=image/svg+xml; ext=svg
else
  die "$source_detail is neither PNG nor SVG by content" 2
fi
log "$kit: logo from $source_kind ($source_detail): $mime, ${size} bytes"

# --- 3. compare with what Hub serves now ------------------------------------

current="$workdir/current"
code=$(curl --silent --show-error --location --max-time 30 --output "$current" \
         --write-out '%{http_code}' "$alias_url" || echo 000)
case "$code" in
  200)
    if cmp -s "$logo" "$current"; then
      if [ "$FORCE" != "true" ]; then
        log "$kit: Hub already serves these exact bytes"
        emit source "$source_kind"; emit action unchanged; emit detail "$source_detail"
        exit 0
      fi
      log "$kit: bytes match but FORCE=true, uploading anyway"
    else
      log "$kit: Hub serves a different logo ($(wc -c <"$current" | tr -d ' ') bytes); will replace it"
    fi
    ;;
  404) log "$kit: Hub has no logo for $repo yet" ;;
  000) die "could not reach $alias_url" ;;
  *)   die "$alias_url answered HTTP $code" ;;
esac

if [ "$DRY_RUN" = "true" ]; then
  log "$kit: dry run, not uploading"
  emit source "$source_kind"; emit action dry-run; emit detail "$source_detail"
  exit 0
fi

# --- 4. upload ---------------------------------------------------------------

[ -n "${HUB_USERNAME:-}" ] && [ -n "${HUB_TOKEN:-}" ] \
  || die "HUB_USERNAME and HUB_TOKEN are required to upload (set DRY_RUN=true to only check)" 2

jwt=$(
  jq -cn --arg username "$HUB_USERNAME" --arg password "$HUB_TOKEN" \
    '{username: $username, password: $password}' |
    curl --fail --silent --show-error --max-time 30 \
      --header 'Content-Type: application/json' --data-binary @- \
      "${HUB_API}/v2/users/login/" |
    jq -r '.token // empty'
)
[ -n "$jwt" ] || die "Hub login returned no token"

response="$workdir/response"
code=$(curl --silent --show-error --max-time 60 --output "$response" --write-out '%{http_code}' \
         --request POST --header "Authorization: JWT $jwt" \
         --form "${HUB_LOGO_FIELD}=@${logo};type=${mime};filename=logo.${ext}" \
         "$alias_url" || echo 000)
case "$code" in
  2*) log "$kit: uploaded (HTTP $code)" ;;
  *)  die "upload to $alias_url failed with HTTP $code: $(head -c 300 "$response")" ;;
esac

emit source "$source_kind"; emit action uploaded; emit detail "$source_detail"
