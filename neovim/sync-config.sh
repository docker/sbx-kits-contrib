#!/usr/bin/env bash
# Copies ~/.config/nvim from the host into the kit's files/ directory so it is
# injected into the sandbox at creation time.  Run this once whenever your
# local config changes and you want the kit to pick it up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/files/home/.config/nvim"
SOURCE="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

if [ ! -d "$SOURCE" ]; then
  echo "No nvim config found at $SOURCE — nothing to sync." >&2
  exit 1
fi

echo "Syncing $SOURCE → $TARGET"
mkdir -p "$TARGET"
cp -r "$SOURCE/." "$TARGET/"
echo "Done. Run 'sbx run <agent> --kit $SCRIPT_DIR <workspace>' to use your config."
