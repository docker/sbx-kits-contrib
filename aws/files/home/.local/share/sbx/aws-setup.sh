#!/bin/sh
# Wire host ~/.aws into the sandbox by symlinking credentials and config.
# Usage: aws-setup.sh <host-aws-dir>
set -eu

HOST_AWS="${1:-}"
if [ -z "$HOST_AWS" ] || [ ! -d "$HOST_AWS" ]; then
  echo "aws-setup: host ~/.aws not found at '$HOST_AWS'" >&2
  exit 1
fi

SANDBOX_AWS="$HOME/.aws"
mkdir -p "$SANDBOX_AWS"

for f in credentials config; do
  src="$HOST_AWS/$f"
  dst="$SANDBOX_AWS/$f"
  [ -e "$src" ] || continue
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    continue
  fi
  ln -sf "$src" "$dst"
  echo "aws-setup: linked $dst -> $src"
done
