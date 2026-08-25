#!/bin/bash
#
# Entry point the sandbox resolves as `devin`; the real CLI is `devin-cli`.
#
# Devin CLI authenticates from ~/.local/share/devin/credentials.toml. When sbx
# has no reusable credential to provision there, this wrapper starts Devin's
# own login flow before launching the agent.

set -uo pipefail

# `devin auth status` exits 0 whether or not a session exists, so its exit code
# cannot gate the login flow — the message it prints is the only signal.
#
# Captured into a variable rather than piped into grep on purpose: `grep -q`
# exits as soon as it matches, which can leave devin-cli killed by SIGPIPE, and
# under `pipefail` that failure becomes the pipeline's status and would mask a
# successful match.
if ! status=$(devin-cli auth status 2>&1); then
    echo "Failed to read Devin authentication status." >&2
    exit 1
fi

case "${status,,}" in
*"not logged in"*)
    echo "Not authenticated. Starting Devin login..."
    # No browser runs in the sandbox, so the default localhost redirect never
    # comes back. --force-manual-token-flow is Devin's own answer for that
    # case (documented for remote and SSH sessions): it prints a URL to open
    # on the host and reads the token back here.
    if ! devin-cli auth login --force-manual-token-flow; then
        echo "Login failed." >&2
        exit 1
    fi
    ;;
esac

# exec so devin-cli replaces this wrapper rather than running underneath it:
# Ctrl-C and SIGTERM then reach the CLI directly instead of a shell that would
# have to forward them.
exec devin-cli "$@"
