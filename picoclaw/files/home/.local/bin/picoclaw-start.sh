#!/bin/sh
# Entrypoint — resolve the Anthropic credential into config.json (picoclaw
# reads keys from config.json, not env), start the gateway if it isn't already
# answering, then drop into the agent CLI.
#
# Invoked through `sh` because files under `files/home/` land 0644: the
# artifact loader does not carry the source exec bit.
set -u

PCH="${PICOCLAW_HOME:-$HOME/.picoclaw}"

sh "$HOME/.local/bin/picoclaw-anthropic-auth.sh"

# A pgrep -f guard would match its own shell's command line and never start the
# gateway, so the health endpoint is the check.
if ! curl -fsS -m 2 http://127.0.0.1:18790/health >/dev/null 2>&1; then
    mkdir -p "$PCH"
    setsid sh -c "/usr/local/bin/picoclaw gateway > $PCH/gateway.log 2>&1" &
fi

exec /usr/local/bin/picoclaw agent
