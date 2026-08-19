#!/usr/bin/env bash
# Report whether a Docker Hub repository has anything published in it.
#
# Usage:
#   scripts/hub-repo-ready.sh <namespace>/<name>
#
#   scripts/hub-repo-ready.sh sbx/kiro-kit
#
# Emits `ready=true` or `ready=false` on stdout, for $GITHUB_OUTPUT.
#
# Why this exists: the Hub overview is repository metadata, and writing it to a
# repository that holds nothing is either an error (the repo does not exist) or
# invisible — Hub only renders an overview "when the repository has at least one
# image". So the sync asks this first and skips rather than failing, which keeps
# main green while `sbx/<kit>-kit` is still waiting on its first push.
#
# Deliberately NOT the same question as "did this run publish something": the
# overview tracks the default branch, and a README fix must reach Hub without
# re-pushing an artifact that would only mint a new digest for identical bytes.
#
# Unauthenticated, so a PRIVATE repository reads as not-ready — it 404s exactly
# like an absent one. That is the safe direction to be wrong in: a skipped sync
# leaves the page alone, where a false "ready" would fail the job.
#
# A transport failure is NOT "not ready": it exits 1, so a flaky network shows up
# as a failure to investigate rather than a silently skipped sync.
#
# Exit codes: 0 answered (see `ready=`) · 1 could not tell · 2 usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <namespace>/<name>" >&2
  exit 2
fi

repo=$1

case "$repo" in
  */*/*|/*|*/) echo "error: '${repo}' is not <namespace>/<name>" >&2; exit 2 ;;
  */*) ;;
  *) echo "error: '${repo}' is not <namespace>/<name>" >&2; exit 2 ;;
esac

# KEY=VALUE on fd 3; stdout to stderr, so curl or jq noise cannot reach it.
exec 3>&1 1>&2

api="https://hub.docker.com/v2/repositories/${repo}/tags/?page_size=1"

body=$(mktemp)
trap 'rm -f "$body"' EXIT

code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 30 "$api" || echo "000")

case "$code" in
  200)
    count=$(jq -r '.count // 0' <"$body")
    if [ "$count" -gt 0 ] 2>/dev/null; then
      echo "${repo}: ${count} tag(s) published"
      echo "ready=true" >&3
    else
      echo "${repo}: exists but holds no tags"
      echo "ready=false" >&3
    fi
    ;;
  404)
    echo "${repo}: not published (absent, or private and therefore invisible here)"
    echo "ready=false" >&3
    ;;
  000)
    echo "error: could not reach ${api}"
    exit 1
    ;;
  *)
    echo "error: ${api} returned HTTP ${code}"
    head -c 400 "$body"
    exit 1
    ;;
esac
