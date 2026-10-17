#!/bin/sh
# Resolve which Anthropic credential the claude_local adapter should use, and
# record it in an env file the entrypoint sources.
#
# The adapter shells out to the Claude Code CLI with the layered env, so the
# CLI's own precedence decides the wire format: an API key in
# ANTHROPIC_API_KEY goes out as `x-api-key`, a subscription login found in
# ~/.claude/.credentials.json as `Authorization: Bearer` with the OAuth betas,
# and Anthropic rejects either shape sent in the wrong header. The kit's apiKey
# block sets ANTHROPIC_API_KEY to the proxy-managed sentinel unconditionally --
# declared by the kit, not by whether a credential exists -- so on an OAuth
# host that sentinel has to go, or the CLI runs in API-key mode against a
# placeholder the proxy has nothing to swap and every run 401s.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" both for an OAuth login
# and for no credential at all, so it cannot tell the two apart. It does
# separate apikey from none, which is the second branch below.
set -eu

# Startup hooks run with a minimal environment and no $HOME (the same reason
# the gateway hook in spec.yaml uses absolute paths), while the entrypoint and
# `sbx exec` shells do have it. This kit's sandbox user is always agent.
HOME="${HOME:-/home/agent}"

STATE_DIR="${PAPERCLIP_HOME:-$HOME/.paperclip}"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

mkdir -p "$STATE_DIR"

# Three credential states, and conflating them is what makes the sandbox
# confusing to operate:
#   oauth         -> drop the sentinel so Claude Code uses the subscription
#                    login the engine materialized, the same way it would on a
#                    host that ran `claude /login`.
#   apikey        -> leave the injected ANTHROPIC_API_KEY sentinel alone.
#   no credential -> drop the sentinel too, so the adapter's environment test
#                    reports no credential rather than an invalid key for one
#                    that never existed.
if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
else
    rm -f "$AUTH_ENV_FILE"
fi

# `sbx exec` runs a non-login shell, so a scripted `claude` call picks this up
# only when it asks for one (`sbx exec -- sh -lc 'claude …'`). The hook stays
# harmless when the file is absent, which is the API-key case above.
if [ -f "$AUTH_ENV_FILE" ] && ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
    printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
fi
