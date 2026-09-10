#!/bin/sh
# Point PicoClaw's seeded config at whichever Anthropic credential the host
# actually holds. PicoClaw reads keys from config.json, not from the
# environment, and it reaches the two credential kinds through two different
# protocols:
#
#   anthropic-messages  api_keys[] -> `x-api-key`          (the seeded default)
#   anthropic + auth_method oauth  -> `Authorization: Bearer` with the
#                                     anthropic-beta oauth header, reading the
#                                     token from ~/.picoclaw/auth.json
#
# Anthropic rejects either credential presented in the wrong header, so an
# OAuth host needs the model entry switched over -- the API-key sentinel alone
# would reach Anthropic unswapped and 401.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" both for an OAuth login
# and for no credential at all, so it cannot tell the two apart.
set -u

# Startup hooks run with a minimal environment and no $HOME (the same reason
# the gateway hook in spec.yaml uses absolute paths), while the entrypoint and
# `sbx exec` shells do have it. This kit's sandbox user is always agent.
HOME="${HOME:-/home/agent}"

PCH="${PICOCLAW_HOME:-$HOME/.picoclaw}"
CFG="$PCH/config.json"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

# Idempotent, and this is the guard: both the entrypoint and the startup hook
# call this script, and a resolved config has no placeholder left to match.
grep -q __ANTHROPIC_API_KEY__ "$CFG" 2>/dev/null || exit 0

if grep -qF "$OAUTH_SENTINEL" "$PCH/auth.json" 2>/dev/null; then
    # The token is already in auth.json, where the `anthropic` protocol's OAuth
    # path reads it; api_keys has to go, or the placeholder stays in a field
    # that protocol ignores. jq rather than sed: this edits structure, and the
    # `shell` template ships jq.
    tmp="$CFG.tmp.$$"
    if jq '(.model_list[] | select(.model == "anthropic-messages/claude-opus-4-6"))
             |= (.model = "anthropic/claude-opus-4-6"
                 | .auth_method = "oauth"
                 | del(.api_keys))' "$CFG" > "$tmp"; then
        mv "$tmp" "$CFG"
    else
        rm -f "$tmp"
    fi
else
    # Absent from a startup hook's minimal environment; the entrypoint runs
    # this script again with the full env, so leaving the placeholder in place
    # is the right no-op rather than an error.
    [ -n "${ANTHROPIC_API_KEY:-}" ] || exit 0
    sed -i "s/__ANTHROPIC_API_KEY__/$ANTHROPIC_API_KEY/" "$CFG"
fi
