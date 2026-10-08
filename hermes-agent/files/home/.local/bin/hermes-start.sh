#!/bin/sh
# Entrypoint. Sources the resolved credential auth state, then execs the
# binary baked into the image.
set -u

AUTH_ENV_FILE="${HERMES_HOME:-$HOME/.hermes}/credential-auth.env"
# Written by hermes-credential-auth.sh at container start; absent means the
# injected ANTHROPIC_API_KEY sentinel is the credential to use as-is.
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

exec "$HOME/.local/bin/hermes" "$@"
