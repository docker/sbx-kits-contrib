#!/bin/sh
# OpenClaw sandbox entrypoint. Starts the gateway if it isn't already
# running, waits for it to report ready, then drops into the interactive
# TUI. Loopback CLI connections are auto-approved for pairing, so no token
# handoff is needed.

GATEWAY_URL="http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}"

# The sandbox runtime seeds its own openclaw.json at create time, which
# can drop gateway.mode — ensure it before the gateway (re)starts.
openclaw config get gateway.mode 2>/dev/null | grep -q local || \
    openclaw config set gateway.mode local

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
