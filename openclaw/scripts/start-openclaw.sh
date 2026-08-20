#!/bin/sh
# OpenClaw sandbox entrypoint. The container's startup command already brought
# the gateway up -- `setup.startup` runs on every container start, not just
# create -- so this waits on the readiness sentinel and drops into the TUI.
#
# It waits rather than bootstrapping in parallel: two concurrent
# openclaw-gateway-up runs both read "no token configured" and each write a
# different one, and `sbx run` creates and attaches in one command. The bounded
# fall-through keeps the safety net for a startup command that failed silently,
# since a non-zero setup.startup command neither fails `sbx create` nor prints
# anything.
set -e

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
READY_FILE="$STATE_DIR/gateway-ready"
BOOTSTRAP=/home/agent/.local/bin/openclaw-gateway-up.sh

i=0
while [ ! -f "$READY_FILE" ]; do
    i=$((i+1))
    if [ $i -ge 45 ]; then
        echo "Gateway not up 45s after container start; bootstrapping here." >&2
        sh "$BOOTSTRAP"
        break
    fi
    sleep 1
done

# The TUI runs the agent in-process rather than delegating every model call to
# the gateway, so it needs the credential in its own environment. The bootstrap
# writes this file only on an OAuth host.
if [ -f "$STATE_DIR/anthropic-oauth.env" ]; then
    . "$STATE_DIR/anthropic-oauth.env"
fi

exec openclaw chat
