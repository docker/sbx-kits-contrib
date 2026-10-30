#!/usr/bin/env bash
# Export committed kit contents; preserve the caller's working tree and secrets.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel)
validation_root=$(mktemp -d "${TMPDIR:-/tmp}/hermes-oauth-XXXXXX")
git -C "$repo_root" archive HEAD hermes-agent hermes-agent-mixin shell |
  tar -x -C "$validation_root"
for kit in hermes-agent hermes-agent-mixin shell; do
  target="check-$kit"
  mv "$validation_root/$kit" "$validation_root/$target"
  for extension in yaml dockerfile; do
    mv "$validation_root/$target/$kit.$extension" \
      "$validation_root/$target/$target.$extension"
  done
done
mkdir "$validation_root/workspace"
printf '%s\n' "$validation_root"
