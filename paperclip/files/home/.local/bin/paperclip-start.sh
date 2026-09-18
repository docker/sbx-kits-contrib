#!/bin/sh
# Entrypoint. Applies the resolved Anthropic auth state, then hands over to the
# image-baked server start script.
#
# This wrapper is kit content rather than a change to start-paperclip.sh
# because the latter is baked into paperclip-image: sourcing the auth decision
# there would only reach a sandbox after the next image publish, while kit
# content reaches an existing sandbox on its next create.
set -u

AUTH_ENV_FILE="${PAPERCLIP_HOME:-$HOME/.paperclip}/anthropic-auth.env"
# Written by paperclip-anthropic-auth.sh at container start; absent means the
# injected ANTHROPIC_API_KEY sentinel is the credential to use as-is.
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

exec /usr/local/bin/paperclip-start "$@"
