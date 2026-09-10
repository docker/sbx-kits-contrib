#!/bin/sh
# OpenClaw sandbox entrypoint. The container's startup command already brought
# the gateway up -- `setup.startup` runs on every container start, not just
# create -- so this waits for it to be ready and drops into the TUI.
#
# It waits rather than bootstrapping in parallel: two concurrent
# openclaw-gateway-up runs both read "no token configured" and each write a
# different one, and `sbx run` creates and attaches in one command. A
# setup.startup command that fails is silent -- it neither fails `sbx create`
# nor prints anything -- so when the wait below times out it opens the TUI and
# points at the logs, rather than starting a second bootstrap to find out.
set -e

# Same reason openclaw-gateway-up.sh does this, and since the Node 24 bump the
# stakes are higher: /usr/local/bin/openclaw is a `#!/usr/bin/env node`
# launcher, and the template still ships Node 22 at /usr/bin/node, which
# openclaw now refuses to run on. Inheriting a /usr/bin-first PATH used to be
# harmless here; now it would fail the TUI while the gateway stayed green.
PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"

GATEWAY_URL="http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}"

# For the progress line only, so an unreadable config costs a name in a message
# and nothing else -- readiness below does not consult it. Read rather than
# hardcoded so it cannot disagree with what openclaw actually wants; the
# authoritative copy is agents.defaults.sandbox in openclaw.json, and
# openclaw-gateway-up.sh is what pulls it.
tool_image=$(jq -r '.agents.defaults.sandbox.docker.image // empty' \
    "$STATE_DIR/openclaw.json" 2>/dev/null || true)

# Readiness is two facts, and both are required:
#
#   /readyz          the gateway is listening
#   gateway-ready    ...and the tool-call image is local
#
# The image half matters because openclaw only inspects that image and throws
# when it is absent -- it never builds or pulls it -- so a turn fails outright
# until the kit's background pull lands. Opening the TUI on the gateway alone
# does not save the wait, it relocates it into the user's first message as an
# error.
#
# The gateway half matters because the sentinel is a file that outlives a
# stop/start: on the next boot it is still there until gateway-up clears it,
# so testing it alone can exec the TUI at a gateway that is not listening,
# which exits non-zero and restart-loops the container.
#
# The bound is generous because a first boot pulls a whole sandbox template,
# and the progress line names the image so it is obvious what is being waited
# on. The old 45s
# bound with a message about the gateway was wrong twice over: the gateway
# answers in about a second, and 45s is nowhere near a cold image pull.
i=0
while :; do
    curl -fsS -m 2 "$GATEWAY_URL/readyz" >/dev/null 2>&1 \
        && [ -f "$STATE_DIR/gateway-ready" ] && break
    i=$((i + 1))
    if [ "$i" = 20 ]; then
        echo "Waiting for the gateway and the tool-call image${tool_image:+ $tool_image}," >&2
        echo "which a first boot pulls. Progress in ~/.openclaw/sandbox-image-pull.log" >&2
    fi
    if [ "$i" -ge 300 ]; then
        # Deliberately does not re-run the bootstrap: a second one alongside a
        # live first clears the sentinel, rewrites anthropic-auth.env and can
        # start a second `openclaw gateway run` against a held state directory.
        # A startup command that died silently shows up here as a TUI that
        # cannot connect, with gateway.log to explain why -- worse than a net,
        # but better than two gateways.
        echo "Not ready after 5m; opening the TUI anyway. Tool calls fail while the" >&2
        echo "image is missing (~/.openclaw/sandbox-image-pull.log); if the gateway" >&2
        echo "never came up, ~/.openclaw/gateway.log has the reason." >&2
        break
    fi
    sleep 1
done

# Credential state for the TUI and whatever it spawns -- this script `exec`s
# into it below, so that is the whole of this export's reach. The TUI itself
# goes through the gateway, which resolved its own credential at startup; this
# matters for anything the TUI runs in-process. Shells arriving via `sbx exec`
# get the same state from the `~/.profile` hook instead, not from here.
if [ -f "$STATE_DIR/anthropic-auth.env" ]; then
    . "$STATE_DIR/anthropic-auth.env"
fi

# `tui`, not `chat`: chat is an alias for `tui --local`, which asks for the
# in-process runtime, and openclaw refuses that while a gateway holds the same
# state directory -- "A Gateway is running for this state directory (pid ...).
# Run without --local to use it". Since this kit always starts a gateway, the
# alias exits 1, which kills the container's main process and puts the sandbox
# in a restart loop. Enforced since 2026.9.3; earlier releases tolerated it.
exec openclaw tui
