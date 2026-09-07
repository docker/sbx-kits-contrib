#!/bin/sh
# Resolve which Anthropic credential Aider should present, and record it in
# an env file the entrypoint sources.
#
# Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
# token sent as `x-api-key`. Aider routes model calls through LiteLLM, which
# picks the header from the *shape* of the key it is handed
# (`optionally_handle_anthropic_oauth` in the `litellm==1.82.3` it pins): a value starting
# `sk-ant-oat` drops `x-api-key` and goes out as Bearer with the OAuth beta
# header, anything else stays an API key. So handing it the OAuth sentinel is
# all it takes -- the proxy swaps that sentinel for the real access token on
# egress to api.anthropic.com.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" both for an OAuth login
# and for no credential at all, so it cannot tell the two apart. It does
# separate apikey from none, which is the second branch below.
set -eu

# Startup hooks run with a minimal environment and no $HOME, while the
# entrypoint and `sbx exec` shells do have it. This kit's sandbox user is
# always agent.
HOME="${HOME:-/home/agent}"

STATE_DIR="$HOME/.config/aider"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

mkdir -p "$STATE_DIR"

# Three credential states, and conflating them is what makes the sandbox
# confusing to operate:
#   oauth         -> hand LiteLLM the OAuth sentinel so it emits Bearer plus
#                    the OAuth beta header.
#   apikey        -> leave the injected ANTHROPIC_API_KEY sentinel alone.
#   no credential -> drop the sentinel. Otherwise Aider treats the
#                    placeholder as a real key and 401s on a credential that
#                    never existed, instead of reporting none configured.
if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    printf 'export ANTHROPIC_API_KEY=%s\n' "$OAUTH_SENTINEL" > "$AUTH_ENV_FILE"
elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
else
    rm -f "$AUTH_ENV_FILE"
fi

# `sbx exec` runs a non-login shell, so a scripted call picks this up only when
# it asks for one (`sbx exec -- sh -lc 'aider …'`). The hook stays harmless
# when the file is absent, which is the API-key case above.
if [ -f "$AUTH_ENV_FILE" ] && ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
    printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
fi
