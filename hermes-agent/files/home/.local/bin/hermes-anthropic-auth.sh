#!/bin/sh
# Resolve which Anthropic wire format Hermes should use, and record it in an env
# file the entrypoint and `sbx exec` shells source.
#
# Anthropic rejects an OAuth token presented as `x-api-key` and an API key
# presented as `Authorization: Bearer`, so the credential's shape decides the
# request Hermes has to emit. Hermes picks it from where the token resolves
# (agent/anthropic_credentials.py, resolve_anthropic_token): ANTHROPIC_TOKEN /
# CLAUDE_CODE_OAUTH_TOKEN, then ANTHROPIC_API_KEY, then
# ~/.claude/.credentials.json. The kit's apiKey block sets ANTHROPIC_API_KEY to
# the proxy-managed sentinel unconditionally -- declared by the kit, not by
# whether a credential exists -- and a non-empty value there deliberately
# shadows any discovered OAuth credential ("an explicit API key must not be
# shadowed by discovered OAuth creds"). So on an OAuth host the sentinel has to
# go, or Hermes never reads the credential file the engine materialized and
# every model call 401s on `x-api-key: proxy-managed`.
#
# The discriminator is that materialized file, not SBX_CRED_ANTHROPIC_MODE:
# that variable reports "none" both for an OAuth login and for no credential at
# all, so it cannot tell the two apart. It does separate apikey from none,
# which is the second branch below.
set -eu

STATE_DIR="${HERMES_HOME:-$HOME/.hermes}"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

mkdir -p "$STATE_DIR"

# Three credential states, and conflating them is what makes the sandbox
# confusing to operate:
#   oauth         -> drop the sentinel so Hermes falls through to
#                    ~/.claude/.credentials.json, which it reads natively and
#                    can refresh, and emits Bearer plus the OAuth betas.
#   apikey        -> leave the injected ANTHROPIC_API_KEY sentinel alone.
#   no credential -> drop the sentinel too. Otherwise Hermes treats the
#                    placeholder as a real key and reports an invalid key for a
#                    credential that never existed, instead of no key at all.
if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
else
    rm -f "$AUTH_ENV_FILE"
fi

# `sbx exec` runs a non-login shell, so a scripted call picks this up only when
# it asks for one (`sbx exec -- sh -lc 'hermes ...'`). The hook stays harmless
# when the file is absent, which is the API-key case above.
if [ -f "$AUTH_ENV_FILE" ] && ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
    printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
fi
