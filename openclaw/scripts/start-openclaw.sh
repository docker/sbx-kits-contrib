#!/bin/sh
# OpenClaw sandbox entrypoint. Starts the gateway if it isn't already
# running, waits for it to report ready, then drops into the interactive
# TUI. Loopback CLI connections are auto-approved for pairing, so no token
# handoff is needed.

GATEWAY_URL="http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}"

# The sandbox runtime seeds its own openclaw.json at create time, which
# can drop gateway.mode/gateway.bind -- ensure both before the gateway
# (re)starts. bind must be "lan" (0.0.0.0), not the "loopback" default:
# the sandbox port-forwarder targets the container's external interface,
# same as it would for any other Docker port mapping.
openclaw config get gateway.mode 2>/dev/null | grep -q local || \
    openclaw config set gateway.mode local
openclaw config get gateway.bind 2>/dev/null | grep -q lan || \
    openclaw config set gateway.bind lan

# Any non-loopback bind is refused without a shared secret, so bind=lan
# above makes gateway auth mandatory, not optional -- without a token the
# gateway exits with EXIT_CONFIG_ERROR before it ever listens. Generate one
# on first boot and persist it to config (not the environment): every later
# `sbx exec` CLI call is a fresh process that resolves the token from
# gateway.auth.token, so an exported variable would only authenticate this
# process tree. auth.mode is left unset deliberately -- it defaults to
# "token" whenever a token resolves.
openclaw config get gateway.auth.token >/dev/null 2>&1 || \
    openclaw config set gateway.auth.token \
        "$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"

if ! curl -fsS "$GATEWAY_URL/readyz" >/dev/null 2>&1; then
    echo "Starting OpenClaw gateway..." >&2
    setsid sh -c "openclaw gateway run >> /home/agent/.openclaw/gateway.log 2>&1" &
    i=0
    until curl -fsS "$GATEWAY_URL/readyz" >/dev/null 2>&1; do
        sleep 1
        i=$((i+1))
        if [ $i -ge 60 ]; then
            echo "Gateway not ready after 60s. Log follows:" >&2
            tail -40 /home/agent/.openclaw/gateway.log 2>/dev/null >&2
            exit 1
        fi
    done
fi

exec openclaw chat
