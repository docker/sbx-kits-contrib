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
# points at the logs rather than starting a second bootstrap to find out.
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
# and nothing else -- readiness below does not consult it. Note the coupling it
# does NOT remove: openclaw-gateway-up.sh hardcodes the same image in
# SANDBOX_TOOL_IMAGE and is what actually pulls it, so changing one without the
# other makes this line name an image nobody fetches. Change both.
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
# Wall clock, not an iteration count: each pass can spend the full `curl -m 2`,
# so counting passes would let "5m" mean fifteen.
announce=$(($(date +%s) + 20))
deadline=$(($(date +%s) + 300))
announced=""
while :; do
    # One probe per pass, reused below. Re-probing at the deadline would let a
    # 2s timeout on a box saturated by the pull report a live gateway as dead.
    gateway_up=""
    curl -fsS -m 2 "$GATEWAY_URL/readyz" >/dev/null 2>&1 && gateway_up=yes
    [ -n "$gateway_up" ] && [ -f "$STATE_DIR/gateway-ready" ] && break
    if [ -z "$announced" ] && [ "$(date +%s)" -ge "$announce" ]; then
        announced=yes
        echo "Waiting for the gateway and the tool-call image${tool_image:+ $tool_image}," >&2
        echo "which a first boot pulls. Progress in ~/.openclaw/sandbox-image-pull.log" >&2
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        # Deliberately no retry. Re-running the bootstrap cost more than the
        # wait it shortened: it cannot tell a dead pull from a slow one, so it
        # can start a second `docker pull`; it blocks a further 180s inside
        # gateway-up with nothing on screen; and the /readyz probe it leaned on
        # for safety is a 2s timeout racing a box saturated by that very pull.
        #
        # What the two causes do need is different endings. A missing image
        # still leaves a usable gateway, so the TUI is worth opening. A dead
        # gateway does not: `openclaw tui` would fail to connect, exit
        # non-zero, and -- being the container's main process -- restart the
        # sandbox straight back into this wait. Hand over a shell instead, so
        # the logs are one command away rather than scrolling past every 5m.
        if [ -z "$gateway_up" ]; then
            echo "Gateway did not come up within 5m. Opening a shell rather than" >&2
            echo "the TUI, which would exit and restart the sandbox in a loop." >&2
            echo "~/.openclaw/gateway.log has the reason. Note the startup" >&2
            echo "command may still be working: check before re-running it, or a" >&2
            echo "second run mints a second gateway token." >&2
            # bash where available: this path exists for reading logs, and dash
            # gives no history and no arrow keys.
            command -v bash >/dev/null 2>&1 && exec bash -l
            exec sh -l
        fi
        echo "Tool-call image still missing after 5m; opening the TUI anyway." >&2
        echo "Tool calls fail until it lands -- progress in" >&2
        echo "~/.openclaw/sandbox-image-pull.log" >&2
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
