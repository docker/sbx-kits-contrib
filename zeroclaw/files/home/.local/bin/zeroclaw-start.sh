#!/bin/sh
# Entrypoint — resolve the Anthropic credential into config.toml, then run the
# daemon. Invoked through `sh` because files under `files/home/` land 0644: the
# artifact loader does not carry the source exec bit.
set -u

sh "$HOME/.local/bin/zeroclaw-anthropic-key.sh"

exec zeroclaw daemon
