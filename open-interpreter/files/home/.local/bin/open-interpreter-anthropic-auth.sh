#!/bin/sh
# Resolve which Anthropic credential Open Interpreter should present, and record it in
# an env file the entrypoint sources.
#
# Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
# token sent as `x-api-key`. Open Interpreter routes model calls through LiteLLM, which
# picks the header from the *shape* of the key it is handed
# (`optionally_handle_anthropic_oauth` in the LiteLLM it resolves (`>=1.41.26,<2`)): a value starting
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

STATE_DIR="$HOME/.config/open-interpreter"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
PROFILE="$HOME/.config/open-interpreter/profiles/default.yaml"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed
# The literal value a proxyManaged API-key credential resolves to -- not a
# real key.
APIKEY_SENTINEL=proxy-managed
# Seeded in the shipped profile; also the model this script switches to and
# back from, so both ends of that swap count as "ours to touch" below.
SEEDED_MODEL=gpt-4o
ANTHROPIC_MODEL=claude-opus-4-6

mkdir -p "$STATE_DIR"

# Three credential states, and conflating them is what makes the sandbox
# confusing to operate:
#   oauth         -> hand LiteLLM the OAuth sentinel so it emits Bearer plus
#                    the OAuth beta header.
#   apikey        -> leave the injected ANTHROPIC_API_KEY sentinel alone.
#   no credential -> drop the sentinel. Otherwise Open Interpreter treats the
#                    placeholder as a real key and 401s on a credential that
#                    never existed, instead of reporting none configured.
if grep -qF "$OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    printf 'export ANTHROPIC_API_KEY=%s\n' "$OAUTH_SENTINEL" > "$AUTH_ENV_FILE"
    anthropic_cred=$OAUTH_SENTINEL
elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
    printf 'unset ANTHROPIC_API_KEY\n' > "$AUTH_ENV_FILE"
    anthropic_cred=
else
    rm -f "$AUTH_ENV_FILE"
    anthropic_cred=$APIKEY_SENTINEL
fi

# `sbx exec` runs a non-login shell, so a scripted call picks this up only when
# it asks for one (`sbx exec -- sh -lc 'interpreter …'`). The hook stays harmless
# when the file is absent, which is the API-key case above.
if [ -f "$AUTH_ENV_FILE" ] && ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
    printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
fi

# The seeded profile pins gpt-4o and declares no api_key, so it never reaches
# Anthropic even when that's the only credential the host holds -- the kit
# also declares an openai credential, and validate_llm_settings only checks
# for a key when the configured model is one of the recognized OpenAI names,
# so a bare Anthropic credential is otherwise silently ignored.
#
# Precedence: redirect the profile at Anthropic only when Anthropic resolved
# and OpenAI did not -- an already-working OpenAI setup keeps its model and
# its own env-var-sourced key untouched. Converge back to the seeded default
# the moment OpenAI becomes available, same guard.
if [ -n "$anthropic_cred" ] && [ "${SBX_CRED_OPENAI_MODE:-none}" = none ]; then
    want_model=$ANTHROPIC_MODEL
    want_key=$anthropic_cred
else
    want_model=$SEEDED_MODEL
    want_key=
fi

current_model=$(sed -n '/^llm:/,/^[^ ]/{/^  model: /{s/^  model: *"\{0,1\}//;s/"\{0,1\}$//;p}}' "$PROFILE" 2>/dev/null | head -1)
current_key=$(sed -n '/^llm:/,/^[^ ]/{/^  api_key: /{s/^  api_key: *"\{0,1\}//;s/"\{0,1\}$//;p}}' "$PROFILE" 2>/dev/null | head -1)

# Only ever touch a model/key pair this script could itself have produced:
# the pristine seeded default, or one of the two Anthropic credential shapes.
# Anything else is a model or key the user set by hand and must survive.
case "$current_model" in
    "$SEEDED_MODEL" | "$ANTHROPIC_MODEL" | "") model_is_ours=1 ;;
    *) model_is_ours=0 ;;
esac
case "$current_key" in
    "$APIKEY_SENTINEL" | "$OAUTH_SENTINEL" | "") key_is_ours=1 ;;
    *) key_is_ours=0 ;;
esac

if [ "$model_is_ours" = 1 ] && [ "$key_is_ours" = 1 ] \
    && { [ "$current_model" != "$want_model" ] || [ "$current_key" != "$want_key" ]; }; then
    tmp="$PROFILE.tmp.$$"
    if awk -v model="$want_model" -v key="$want_key" '
        /^llm:/ {
            print
            print "  model: \"" model "\""
            if (key != "") print "  api_key: \"" key "\""
            in_llm = 1
            next
        }
        in_llm && /^[^ ]/ { in_llm = 0 }
        in_llm && /^  model: / { next }
        in_llm && /^  api_key: / { next }
        { print }
    ' "$PROFILE" > "$tmp"; then
        mv "$tmp" "$PROFILE"
    else
        rm -f "$tmp"
    fi
fi
