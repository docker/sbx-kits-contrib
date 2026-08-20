#!/bin/sh
# OpenClaw sandbox entrypoint. The container's startup command already brought
# the gateway up -- `setup.startup` runs on every container start, not just
# create -- so this normally waits on the readiness sentinel and drops straight
# into the interactive TUI.
#
# It waits rather than bootstrapping in parallel. Two concurrent
# openclaw-gateway-up runs both read "no token configured" and each write a
# different one; last write wins, and a gateway that read config in between
# then holds a token no later CLI call presents. `sbx run` creates and attaches
# in one command, so that overlap is on the default path, not a corner case.
#
# The bounded fall-through keeps the safety net for a startup command that
# failed: a non-zero setup.startup command neither fails `sbx create` nor
# prints anything, so without it a silent failure would hang here forever.
set -e

READY_FILE="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}/gateway-ready"
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

exec openclaw chat
