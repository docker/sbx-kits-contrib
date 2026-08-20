#!/bin/sh
# OpenClaw sandbox entrypoint. The container's startup command already
# brought the gateway up, so this is normally one /readyz probe; it is
# repeated here so an attach after a stop/start still gets a live gateway.
# Then drop into the interactive TUI. Loopback CLI connections authenticate
# with the token openclaw-gateway-up persisted to config, so there is no
# token handoff on the operator's side.
set -e

/usr/local/bin/openclaw-gateway-up

exec openclaw chat
