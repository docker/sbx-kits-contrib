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

# The TUI runs the agent in-process, so it needs the credential state too --
# an OAuth token when the host has one, or ANTHROPIC_API_KEY unset when the
# host has no credential at all.
if [ -f "$STATE_DIR/anthropic-auth.env" ]; then
    . "$STATE_DIR/anthropic-auth.env"
fi

exec openclaw chat
