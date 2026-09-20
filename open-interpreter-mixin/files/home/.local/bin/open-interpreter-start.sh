#!/bin/sh
# Entrypoint. Applies the resolved Anthropic auth state, then execs Open Interpreter.
#
# Invoked through `sh` because the scripts under /home/agent land 0644: the
# kit's recipe copies the files/home/ tree without an exec bit.
set -u

AUTH_ENV_FILE="$HOME/.config/open-interpreter/anthropic-auth.env"
# Written by open-interpreter-anthropic-auth.sh at container start; absent means the
# injected ANTHROPIC_API_KEY sentinel is the credential to use as-is.
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

exec "$HOME/.local/bin/interpreter" "$@"
