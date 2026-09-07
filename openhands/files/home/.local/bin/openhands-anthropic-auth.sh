#!/bin/sh
# Resolve which Anthropic credential OpenHands should present, and record it in
# an env file the entrypoint sources.
#
# Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
# token sent as `x-api-key`. OpenHands routes model calls through LiteLLM, which
# picks the header from the *shape* of the key it is handed
# (`optionally_handle_anthropic_oauth` in the LiteLLM openhands-sdk pins (`>=1.93.0`)): a value starting
# `sk-ant-oat` drops `x-api-key` and goes out as Bearer with the OAuth beta
# header, anything else stays an API key. So handing it the OAuth sentinel is
# all it takes -- the proxy swaps that sentinel for the real access token on
# egress to api.anthropic.com.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" both for an OAuth login
# and for no credential at all, so it cannot tell the two apart. It does
# separate apikey from none, which is the second branch below.
#
# ANTHROPIC_API_KEY alone never reaches the OpenHands CLI: it reads its LLM
# config from ~/.openhands/agent_settings.json (a pydantic-serialized Agent
# spec, not the legacy `llm_config` shape) or, with --override-with-envs
# (openhands-start.sh always passes it), from LLM_API_KEY/LLM_MODEL. Those are
# the two variables that must carry the resolved credential.
set -eu

# Startup hooks run with a minimal environment and no $HOME, while the
# entrypoint and `sbx exec` shells do have it. This kit's sandbox user is
# always agent.
HOME="${HOME:-/home/agent}"

STATE_DIR="$HOME/.config/openhands"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed
# The literal value a proxyManaged API-key credential resolves to -- not a
# real key. Read as a constant, not from $ANTHROPIC_API_KEY: a startup hook
# runs in a minimal environment that may not expose that var yet, and
# misreading it as absent would wrongly land OpenHands in the
# missing-credential state.
APIKEY_SENTINEL=proxy-managed
# LLM_API_KEY/LLM_MODEL only ever construct a transient, unpersisted Agent;
# once a real one is on disk, its saved model and key must win over ours.
AGENT_SETTINGS="$HOME/.openhands/agent_settings.json"
ANTHROPIC_MODEL=claude-opus-4-6

mkdir -p "$STATE_DIR"

{
    # Three credential states, and conflating them is what makes the sandbox
    # confusing to operate:
    #   oauth         -> hand LiteLLM the OAuth sentinel so it emits Bearer plus
    #                    the OAuth beta header.
    #   apikey        -> leave the injected ANTHROPIC_API_KEY sentinel alone.
    #   no credential -> drop the sentinel. Otherwise OpenHands treats the
    #                    placeholder as a real key and 401s on a credential that
    #                    never existed, instead of reporting none configured.
    if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
        credential=$OAUTH_SENTINEL
        printf 'export ANTHROPIC_API_KEY=%s\n' "$credential"
    elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
        credential=
        printf 'unset ANTHROPIC_API_KEY\n'
    else
        credential=$APIKEY_SENTINEL
    fi

    if [ -n "$credential" ] && [ ! -f "$AGENT_SETTINGS" ]; then
        printf 'export LLM_API_KEY=%s\n' "$credential"
        printf 'export LLM_MODEL=%s\n' "$ANTHROPIC_MODEL"
    else
        printf 'unset LLM_API_KEY\n'
        printf 'unset LLM_MODEL\n'
    fi
} > "$AUTH_ENV_FILE"

# `sbx exec` runs a non-login shell, so a scripted call picks this up only when
# it asks for one (`sbx exec -- sh -lc 'openhands …'`).
if ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
    printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
fi
