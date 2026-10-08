#!/usr/bin/env bash
# Print every kit directory at the repo root, one per line, sorted.
#
# A kit is any directory holding a descriptor named after itself —
# `<dir>/<dir>.yaml`. No registration list, so adding a kit needs no change
# here or in any of this script's callers.
#
# Why the name has to match the directory: a v3 kit is a single OCI image
# published as <registry>/<namespace>/<dir>, and the directory name is
# the only thing that reference is derived from. A descriptor free to be called
# anything would let a kit build under one name and publish under another. It
# is also how the companion recipe is found — the frontend pairs `<dir>.yaml`
# with `<dir>.dockerfile` by filename stem — so the stem is already load-bearing
# before publishing ever sees it.
#
# The stem rule is also what keeps non-kit directories out without an ignore
# list: `spec/`, `tck/`, `scripts/` and `skills/` hold no file named after
# themselves, so they are not kits by construction rather than by exception.
#
# RESERVED SUFFIXES. A kit may not be named `*-kit` or `*-image`; the reason is
# delegated to check-kit-name.sh, which is also what the two scripts that
# COMPOSE a published reference call, and what check-release-tag.sh calls for a
# name that arrived in a git tag. A guard here alone would not cover those.
#
# Checked in a FIRST PASS, before a single name is printed, so the refusal
# cannot be read as a short list. Callers consume this through process
# substitution (`done < <(./scripts/discover-kits.sh)`), which discards the
# exit status entirely — emitting as we validate would hand tck.yml a truncated
# kit list and a green run. Nothing is printed unless every name is legal.
#
# Used by every workflow that needs the full kit list — build-and-publish-kits.yml's
# own discovery, hub-overview.yml's docs-triggered sync, and tck.yml's kit
# detection — so what counts as a kit is defined in exactly one place.
set -euo pipefail

# Anchor to the repo root so this works regardless of the caller's cwd —
# run from a kit subdirectory otherwise, the glob below matches nothing and
# the script silently prints an empty list instead of erroring.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR/.."

# `*/` rather than `*` so only directories are considered: a stray top-level
# file would otherwise be probed as though it were a kit directory.
#
# sort -u de-dupes a kit carrying both `.yaml` and `.yml` (mid-rename, say),
# which would otherwise list it twice and spawn two matrix legs racing to push
# the same tags.
kits=()
for dir in */; do
  kit=${dir%/}
  if [ -f "$kit/$kit.yaml" ] || [ -f "$kit/$kit.yml" ]; then
    kits+=("$kit")
  fi
done

for kit in ${kits[@]+"${kits[@]}"}; do
  "$SCRIPT_DIR/check-kit-name.sh" "$kit" || exit 1
done

# The empty case is handled before printf rather than by it: `printf '%s\n'`
# with NO operands still applies the format once and writes a bare newline, so a
# repository with no kit directories would emit one empty line instead of
# nothing. A caller doing `kits=$(discover-kits.sh | jq -R . | jq -sc .)` then
# gets `[""]` rather than `[]`, passes its own `!= '[]'` guard, and spawns a
# matrix leg whose kit name is the empty string.
[ ${#kits[@]} -gt 0 ] || exit 0

printf '%s\n' "${kits[@]}" | sort -u
