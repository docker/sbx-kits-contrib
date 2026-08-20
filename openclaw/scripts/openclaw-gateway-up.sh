#!/bin/sh
# Bring the OpenClaw gateway up, idempotently.
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

if gateway_ready; then
    exit 0
fi

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
