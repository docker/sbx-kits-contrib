#!/bin/sh
# Entrypoint. Applies the resolved Anthropic auth state, then execs OpenHands.
#
# Invoked through `sh` because files under `files/home/` land 0644: the
# artifact loader does not carry the source exec bit.
set -u

# Re-run the resolver here, not just source its output: the entrypoint is
# guaranteed the full container environment, while the setup.startup hook
# that already ran it once may not be. The resolver is idempotent, so running
# it twice only means the entrypoint's result is the one that counts.
sh "$HOME/.local/bin/openhands-anthropic-auth.sh"

AUTH_ENV_FILE="$HOME/.config/openhands/anthropic-auth.env"
# shellcheck source=/dev/null
[ -f "$AUTH_ENV_FILE" ] && . "$AUTH_ENV_FILE"

# --override-with-envs: without it, openhands ignores LLM_API_KEY/LLM_MODEL
# entirely and either falls back to a persisted ~/.openhands/agent_settings.json
# or, on a fresh sandbox, opens the interactive first-run settings form -- there
# is no non-interactive way to hand it a credential otherwise.
exec "$HOME/.local/bin/openhands" --override-with-envs "$@"
