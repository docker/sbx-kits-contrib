#!/bin/sh
# Substitute the Anthropic credential sentinel that matches the host's stored
# credential into config.toml, which is where v0.8.0 expects it: that release
# dropped the legacy ANTHROPIC_API_KEY env fallbacks.
#
# ZeroClaw reads one field for both credential kinds and picks the wire format
# from the token's shape (AnthropicModelProvider::is_setup_token): a value
# starting `sk-ant-oat01-` goes out as `Authorization: Bearer` with the OAuth
# betas and the Claude Code system prefix Anthropic requires, anything else as
# `x-api-key`. Anthropic rejects either shape sent in the wrong header, so the
# sentinel written here has to match the credential the host actually holds.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" both for an OAuth login
# and for no credential at all, so it cannot tell the two apart.
set -u

# Startup hooks run with a minimal environment and no $HOME (the same reason
# the gateway hook in spec.yaml uses absolute paths), while the entrypoint and
# `sbx exec` shells do have it. This kit's sandbox user is always agent.
HOME="${HOME:-/home/agent}"

CFG="$HOME/.zeroclaw/config.toml"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

# Idempotent, and this is the guard: both the entrypoint and the startup hook
# call this script, and a substituted config has no placeholder left to match.
grep -q __ANTHROPIC_API_KEY__ "$CFG" 2>/dev/null || exit 0

if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    KEY=$OAUTH_SENTINEL
else
    # Absent from a startup hook's minimal environment; the entrypoint runs
    # this script again with the full env, so leaving the placeholder in place
    # is the right no-op rather than an error.
    KEY="${ANTHROPIC_API_KEY:-}"
fi

[ -n "$KEY" ] || exit 0
sed -i "s/__ANTHROPIC_API_KEY__/$KEY/" "$CFG"
