#!/usr/bin/env bash
# Print every kit directory at the repo root, one per line, sorted.
#
# A kit is any directory with a spec.yaml or spec.yml — no registration list,
# so adding a kit needs no change here or in any of this script's callers.
# sort -u de-dupes: a kit could carry both spec.yaml and spec.yml (mid
# migration, say), which would otherwise list it twice and spawn two matrix
# legs racing to push the same tags.
#
# Used by every workflow that needs the full kit list — build-and-publish-kits.yml's
# own discovery and hub-overview.yml's docs-triggered sync — so what counts as
# a kit is defined in exactly one place.
set -euo pipefail

for f in */spec.yaml */spec.yml; do
  [ -f "$f" ] || continue
  dirname "$f"
done | sort -u
