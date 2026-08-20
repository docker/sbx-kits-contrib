#!/bin/sh
# Bring the OpenClaw gateway up, idempotently.
#
# Shipped as kit content (files/home/), not baked into the image, so a fix
# here reaches an existing sandbox on its next create without republishing
# docker.io/sbx/openclaw-image.
#
# Called from two places: `setup.startup` in spec.yaml, so a *created*
# sandbox has a live gateway -- and therefore a live published port and a
# working `sbx exec <sandbox> -- openclaw ...` -- without anyone attaching
# the TUI, and the interactive entrypoint, which needs the same guarantee
# after a stop/start. Both paths are a single /readyz probe once the gateway
# is already up.
set -e

# Startup commands run with a minimal PATH that may not include the npm
# global bin dir; /usr/local/bin/openclaw is the symlink pinned for exactly
# that reason (see Dockerfile). curl/setsid/od live in /usr/bin.
PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
GATEWAY_URL="http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}"

# /readyz is unauthenticated by design, so this stays a valid readiness
# probe after the token below is in place.
gateway_ready() {
    curl -fsS -m 2 "$GATEWAY_URL/readyz" >/dev/null 2>&1
}

# `setup.startup` re-runs on every container start (SPEC-v2 5.6) and
# $STATE_DIR survives a stop/start, so last boot's sentinel outlives the
# gateway that wrote it. Clear it before the slow config work below: while
# /readyz is not green the sentinel must read absent, or a consumer polling it
# (README, tck.yaml readyFile) races into the very failure it exists to
# prevent.
gateway_ready || rm -f "$STATE_DIR/gateway-ready"

# The sandbox runtime seeds its own openclaw.json at create time, which can
# drop gateway.mode/gateway.bind -- ensure both before the gateway
# (re)starts. bind must be "lan" (0.0.0.0), not the "loopback" default: the
# port-forwarder targets the container's external interface, same as it
# would for any other Docker port mapping.
openclaw config get gateway.mode 2>/dev/null | grep -q local || \
    openclaw config set gateway.mode local
openclaw config get gateway.bind 2>/dev/null | grep -q lan || \
    openclaw config set gateway.bind lan

# OpenClaw refuses any non-loopback bind that has no shared secret, exiting
# with a config error before it ever listens, so bind=lan above makes the
# token mandatory rather than optional. Persist it to config rather than
# exporting OPENCLAW_GATEWAY_TOKEN: every `sbx exec` is a fresh process that
# would not inherit the variable, while config is read by every invocation,
# so the whole CLI surface inside the sandbox stays authenticated. Generated
# per sandbox rather than baked into files/home/.openclaw/openclaw.json so
# it is not a static secret shared by every sandbox from this kit.
# gateway.auth.mode is left unset -- it defaults to "token" whenever a token
# resolves.
openclaw config get gateway.auth.token >/dev/null 2>&1 || \
    openclaw config set gateway.auth.token \
        "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# Anthropic sends the credential differently depending on its shape, and
# OpenClaw picks the shape from the token itself: any value containing
# "sk-ant-oat" goes out as `Authorization: Bearer` with the OAuth beta headers,
# anything else as `x-api-key` (upstream extensions/anthropic/stream-wrappers.ts
# isAnthropicOAuthApiKey, register.runtime.ts). Anthropic rejects an OAuth token
# presented as `x-api-key`, so on an OAuth host the apiKey sentinel alone is not
# enough -- OpenClaw has to be handed an OAuth-shaped token to emit the right
# request, and the proxy swaps the real bearer in at egress.
#
# The discriminator is the materialized credential file, not
# SBX_CRED_ANTHROPIC_MODE: that variable reports "none" even when this OAuth
# credential resolves and injects fine, so it cannot tell oauth from apikey.
# ANTHROPIC_OAUTH_TOKEN takes precedence over ANTHROPIC_API_KEY upstream
# (src/secrets/provider-env-vars.ts), so it must stay unset on an API-key host
# or OpenClaw would send a sentinel the proxy has nothing to swap. Exported for
# the gateway process below, which is what performs model calls.
#
# The sentinel must match spec.yaml credentials[].oauth.sentinels.accessToken.
ANTHROPIC_OAUTH_SENTINEL=sk-ant-oat01-proxy-managed
OAUTH_ENV_FILE="$STATE_DIR/anthropic-oauth.env"
if grep -qF "$ANTHROPIC_OAUTH_SENTINEL" "$HOME/.claude/.credentials.json" 2>/dev/null; then
    ANTHROPIC_OAUTH_TOKEN="$ANTHROPIC_OAUTH_SENTINEL"
    export ANTHROPIC_OAUTH_TOKEN
    # The token cannot live only in this process: the TUI runs the agent
    # in-process and every `sbx exec` is a fresh shell, so both would fall back
    # to the API-key sentinel and fail with a misleading rate-limit error.
    printf "export ANTHROPIC_OAUTH_TOKEN=%s\\n" "$ANTHROPIC_OAUTH_SENTINEL" > "$OAUTH_ENV_FILE"
    if ! grep -qF "$OAUTH_ENV_FILE" "$HOME/.profile" 2>/dev/null; then
        printf "[ -f %s ] && . %s\\n" "$OAUTH_ENV_FILE" "$OAUTH_ENV_FILE" >> "$HOME/.profile"
    fi
else
    # API-key host: never leave the OAuth var set, it outranks ANTHROPIC_API_KEY.
    rm -f "$OAUTH_ENV_FILE"
fi

if ! gateway_ready; then
    echo "Starting OpenClaw gateway..." >&2
    setsid sh -c "openclaw gateway run >> $STATE_DIR/gateway.log 2>&1" &
    i=0
    until gateway_ready; do
        sleep 1
        i=$((i+1))
        if [ $i -ge 60 ]; then
            echo "Gateway not ready after 60s. Log follows:" >&2
            tail -40 "$STATE_DIR/gateway.log" 2>/dev/null >&2
            exit 1
        fi
    done
fi

# Readiness sentinel for scripted consumers. A `setup.startup` command does
# not block `sbx exec`, so a caller that runs `openclaw ...` immediately
# after the container starts can beat the gateway to it and see
# GatewayCredentialsRequiredError. testdata/tck.yaml polls this path as its
# readyFile before the prompt subtest, for the same reason.
: > "$STATE_DIR/gateway-ready"
