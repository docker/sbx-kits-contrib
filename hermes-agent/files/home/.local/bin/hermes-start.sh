#!/bin/sh
# Entrypoint. Applies the resolved Anthropic auth state, then waits for the
# background install to finish before exec-ing the binary it installs.
set -u

AUTH_ENV_FILE="${HERMES_HOME:-$HOME/.hermes}/anthropic-auth.env"
# Written by hermes-anthropic-auth.sh at container start; absent means the
# injected ANTHROPIC_API_KEY sentinel is the credential to use as-is.
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

if ! [ -f "$HOME/.hermes-installed" ]; then
    echo "Waiting for Hermes Agent installation (~3 min)..." >&2
    until [ -f "$HOME/.hermes-installed" ]; do sleep 3; done
fi

exec "$HOME/.local/bin/hermes" "$@"
