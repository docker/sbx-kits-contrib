#!/bin/sh
# Resolve which Anthropic wire format Hermes should use, and record it in an env
# file the entrypoint and `sbx exec` shells source. Also decides which
# *provider* Hermes' own auto-detection should land on, and overrides it in
# config.yaml for the one case that detection cannot see at all.
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
#
# Provider selection is a separate, second problem. hermes_cli/auth.py's
# resolve_provider() picks OpenRouter over everything else -- including a
# logged-in Anthropic OAuth session -- the moment OPENAI_API_KEY or
# OPENROUTER_API_KEY looks like a usable secret. This kit's openai and
# openrouter credentials are also proxy-managed and also injected
# unconditionally, so both sentinels are present whether or not the host
# actually bound either service, and upstream's placeholder filter does not
# recognize "proxy-managed" as one to reject. Left alone, an Anthropic-only
# host is silently routed to OpenRouter with no real key and 401s "Missing
# Authentication header" -- confirmed against a real sandbox, where the
# request reached openrouter.ai unauthenticated rather than api.anthropic.com.
#
# Two fixes below close it. First, unset whichever of those two sentinels the
# host did not actually bind (SBX_CRED_OPENAI_MODE / SBX_CRED_OPENROUTER_MODE
# are the proxy's own signal of that, independent of the sentinel string
# itself), so upstream's detection can no longer mistake either for a real
# key. That alone is enough when Anthropic is bound as a plain API key --
# once the other two sentinels are gone, upstream's provider-specific-env-key
# tier already recognizes ANTHROPIC_API_KEY correctly. It is NOT enough for an
# Anthropic OAuth login: upstream's auto-detection has no tier that reads
# ~/.claude/.credentials.json at all, so a login there is invisible to
# resolve_provider() no matter how clean the other sentinels are, and it falls
# through to "no provider configured" instead of Anthropic. That case needs
# the config.yaml override at the bottom of this script.
set -eu

# Startup hooks run with a minimal environment and no $HOME (the same reason
# the gateway hook in spec.yaml uses absolute paths), while the entrypoint and
# `sbx exec` shells do have it. This kit's sandbox user is always agent.
HOME="${HOME:-/home/agent}"

STATE_DIR="${HERMES_HOME:-$HOME/.hermes}"
AUTH_ENV_FILE="$STATE_DIR/anthropic-auth.env"
HERMES_BIN="$HOME/.local/bin/hermes"
# Must match credentials[].oauth.sentinels.accessToken in spec.yaml.
OAUTH_SENTINEL=sk-ant-oat01-proxy-managed

mkdir -p "$STATE_DIR"
rm -f "$AUTH_ENV_FILE"

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
    anthropic_cred=oauth
    printf 'unset ANTHROPIC_API_KEY\n' >> "$AUTH_ENV_FILE"
elif [ "${SBX_CRED_ANTHROPIC_MODE:-none}" = none ]; then
    anthropic_cred=none
    printf 'unset ANTHROPIC_API_KEY\n' >> "$AUTH_ENV_FILE"
else
    anthropic_cred=apikey
fi

# Same placeholder problem as ANTHROPIC_API_KEY above, for the other two
# credentials this kit declares -- except neither has an OAuth shape to
# preserve, so "not genuinely bound" always means "drop the sentinel".
if [ "${SBX_CRED_OPENAI_MODE:-none}" = none ]; then
    openai_bound=0
    printf 'unset OPENAI_API_KEY\n' >> "$AUTH_ENV_FILE"
else
    openai_bound=1
fi
if [ "${SBX_CRED_OPENROUTER_MODE:-none}" = none ]; then
    openrouter_bound=0
    printf 'unset OPENROUTER_API_KEY\n' >> "$AUTH_ENV_FILE"
else
    openrouter_bound=1
fi

# `sbx exec` runs a non-login shell, so a scripted call picks this up only when
# it asks for one (`sbx exec -- sh -lc 'hermes ...'`). The hook stays harmless
# when the file is absent, which is the case where all three credentials are
# genuinely bound (or genuinely absent and there is nothing to unset).
if [ -s "$AUTH_ENV_FILE" ]; then
    if ! grep -qF "$AUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
        printf '[ -f %s ] && . %s\n' "$AUTH_ENV_FILE" "$AUTH_ENV_FILE" >> "$HOME/.profile"
    fi
else
    rm -f "$AUTH_ENV_FILE"
fi

# Provider pin, for the OAuth gap the sentinel fix above cannot reach.
# cli-config.yaml.example -- the template install.sh copies verbatim into
# config.yaml -- ships `provider: "auto"` and `default:
# "anthropic/claude-opus-4.6"`. "auto" defers to resolve_provider(), and by
# this point in the script that can only still land on OpenRouter if the host
# genuinely bound it (the sentinel fix above ruled out the false positive), so
# doing nothing is correct in every state except one: an Anthropic OAuth login
# with neither OpenAI nor OpenRouter bound, where resolve_provider() has no
# tier that would ever pick Anthropic. Force it there, and nowhere else.
#
# Only ever touch the provider/model pair this script could itself have
# produced -- the template's original values, or the values it sets below.
# Anything else is a choice the user made with `hermes model` and must
# survive a credential change or a container restart untouched.
if [ -x "$HERMES_BIN" ]; then
    PRISTINE_PROVIDER=auto
    PRISTINE_MODEL='anthropic/claude-opus-4.6'
    OUR_PROVIDER=anthropic
    OUR_MODEL=claude-opus-4-6

    current_provider=$("$HERMES_BIN" config get model.provider 2>/dev/null) || current_provider=""
    current_model=$("$HERMES_BIN" config get model.default 2>/dev/null) || current_model=""

    provider_is_ours=0
    case "$current_provider" in
        "$PRISTINE_PROVIDER" | "$OUR_PROVIDER" | "") provider_is_ours=1 ;;
    esac
    model_is_ours=0
    case "$current_model" in
        "$PRISTINE_MODEL" | "$OUR_MODEL" | "") model_is_ours=1 ;;
    esac

    if [ "$provider_is_ours" = 1 ] && [ "$model_is_ours" = 1 ]; then
        if [ "$anthropic_cred" != none ] && [ "$openai_bound" = 0 ] && [ "$openrouter_bound" = 0 ]; then
            want_provider=$OUR_PROVIDER
            want_model=$OUR_MODEL
        else
            want_provider=$PRISTINE_PROVIDER
            want_model=$PRISTINE_MODEL
        fi
        [ "$current_provider" = "$want_provider" ] || "$HERMES_BIN" config set model.provider "$want_provider" >/dev/null 2>&1 || true
        [ "$current_model" = "$want_model" ] || "$HERMES_BIN" config set model.default "$want_model" >/dev/null 2>&1 || true
    fi
fi
