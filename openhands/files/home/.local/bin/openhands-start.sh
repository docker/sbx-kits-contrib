#!/bin/sh
# Entrypoint. Applies the resolved Anthropic auth state, then execs OpenHands.
#
# Invoked through `sh` because files under `files/home/` land 0644: the
# artifact loader does not carry the source exec bit.
set -u

AUTH_ENV_FILE="$HOME/.config/openhands/anthropic-auth.env"
# Written by openhands-anthropic-auth.sh at container start; absent means the
# injected ANTHROPIC_API_KEY sentinel is the credential to use as-is.
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

exec "$HOME/.local/bin/openhands" "$@"
