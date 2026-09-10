#!/bin/sh
# OpenClaw sandbox entrypoint. The container's startup command already brought
# the gateway up -- `setup.startup` runs on every container start, not just
# create -- so this waits for it to answer /readyz and drops into the TUI.
#
# It waits rather than bootstrapping in parallel: two concurrent
# openclaw-gateway-up runs both read "no token configured" and each write a
# different one, and `sbx run` creates and attaches in one command. The bounded
# fall-through keeps the safety net for a startup command that failed silently,
# since a non-zero setup.startup command neither fails `sbx create` nor prints
# anything.
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
BOOTSTRAP=/home/agent/.local/bin/openclaw-gateway-up.sh

# Wait on the gateway itself, not on $STATE_DIR/gateway-ready. That sentinel
# means "gateway serving AND the tool-call image is local", because scripted
# consumers (testdata/tck.yaml's readyFile, the README's scripting advice) want
# both before they drive an agent. This entrypoint wants less: it is about to
# open a TUI against the gateway, and a tool-call image that is still
# downloading does not stop that. Waiting on the sentinel here made a first
# boot print the bootstrap warning below and stall for the length of an image
# pull -- minutes -- with a perfectly healthy gateway already listening.
# This net is for a startup command that died silently -- not for one that is
# merely slow. Any wall-clock guess races it: gateway-up spends unbounded time
# before its own 60s /readyz wait even begins (cold `openclaw config` spawns,
# `docker image inspect` against a backgrounded pull), and the clock here
# starts at container start rather than at dispatch. Fire on the bootstrap
# being *gone* instead. Running a second one alongside a live first would clear
# the sentinel, rewrite anthropic-auth.env and start a second
# `openclaw gateway run` against a state directory the first one holds.
# The wrapper is not the whole story: gateway-up launches the gateway with
# setsid, so the gateway outlives it, and the wrapper exits 1 at its own 60s
# /readyz timeout while a slow gateway is still starting. Watching only the
# wrapper would read that as "died silently" and bootstrap over a live gateway.
# Either process means startup is still in progress. `openclaw-gateway` covers
# both the wrapper (openclaw-gateway-up.sh) and the gateway, which retitles
# itself; the "gateway run" arm catches the setsid `sh -c` form before any
# retitle takes effect.
startup_in_progress() {
    for d in /proc/[0-9]*; do
        [ -r "$d/cmdline" ] || continue
        case "$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)" in
            *openclaw-gateway*|*"gateway run"*) return 0 ;;
        esac
    done
    return 1
}

# A floor as well as a ceiling. The floor is for dispatch latency: this
# entrypoint and `setup.startup` both begin at container start, and if the
# first probe lands before the dispatcher has spawned anything then nothing
# matches yet -- bootstrapping there would put two runs in flight, each
# minting a different gateway token. The ceiling only stops a wedged startup
# holding the attach forever; it does not bootstrap again, because a second
# run alongside a live one is the harm described above.
grace=$(($(date +%s) + 30))
deadline=$(($(date +%s) + 300))
until curl -fsS -m 2 "$GATEWAY_URL/readyz" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$grace" ] && ! startup_in_progress; then
        echo "Gateway is not up and its startup command is gone; bootstrapping here." >&2
        # `|| true` because this script runs under `set -e`: an exit 1 here
        # would abort before the TUI runs, discarding the gateway.log tail
        # gateway-up just printed. This does not rescue a gateway that cannot
        # start -- `openclaw tui` will fail too -- it just makes the failure
        # arrive with its diagnostics attached rather than as a bare exit.
        sh "$BOOTSTRAP" || true
        break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "Gateway still not up after 300s; opening the TUI anyway." >&2
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
