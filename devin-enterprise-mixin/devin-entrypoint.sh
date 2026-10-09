#!/bin/bash
# Keep the base Devin wrapper's auth checks and login flow. Enterprise
# credentials stay on disk because proxy-managed auth is unavailable.
# The real CLI is installed alongside this wrapper as devin-cli.
#
# `set -e` is deliberately NOT set. Every failure below is checked explicitly,
# and several checks depend on reading a non-zero status rather than dying on
# it.
set -uo pipefail

credentials_file="${HOME}/.local/share/devin/credentials.toml"

# The four states the credential file can be in, as one word. They are
# exhaustive and mutually exclusive, which is what lets the dispatch below
# close with a plain `else`.
#
#   absent     — no file, or no windsurf_api_key line in it
#   empty      — the key is present but blank, which the CLI treats as
#                logged-in-with-nothing and will not overwrite on its own
#   sentinel   — a proxy placeholder left by the managed wrapper
#   credential — a real key sitting in the container
credential_state() {
    if [[ ! -f "${credentials_file}" ]] ||
        ! grep -Eq '^[[:space:]]*windsurf_api_key[[:space:]]*=' "${credentials_file}"; then
        echo absent
    elif grep -Eq '^[[:space:]]*windsurf_api_key[[:space:]]*=[[:space:]]*""[[:space:]]*$' "${credentials_file}"; then
        echo empty
    elif grep -Fqx 'windsurf_api_key = "devin-proxy-managed"' "${credentials_file}"; then
        echo sentinel
    else
        echo credential
    fi
}

# `devin-cli auth status` exits 0 whether or not a session exists in some
# releases, so its message is checked as well as its status. It is captured
# into a variable rather than piped into grep: `grep -q` exits on first match,
# which can leave devin-cli killed by SIGPIPE, and under `pipefail` that
# failure becomes the pipeline's status and would mask the successful match.
state=$(credential_state)
login_required=false
if [[ "${state}" == absent || "${state}" == empty ]]; then
    login_required=true
elif [[ "${state}" == sentinel ]]; then
    # The placeholder is only as good as the key the host holds behind it. If
    # that key has been revoked or rotated away, the file is worthless — drop
    # it and log in again rather than starting an agent that will fail on its
    # first request.
    if ! status=$(devin-cli auth status 2>&1) ||
        [[ "${status,,}" == *"failed to fetch"* ]] ||
        [[ "${status,,}" == *"not logged in"* ]]; then
        rm -f "${credentials_file}"
        state=absent
        login_required=true
    fi
else
    # state == credential. A real key is on disk; find out whether it works
    # before deciding. Unlike the sentinel branch above, a transport failure
    # here is fatal rather than a trigger for re-login: this key may be the
    # user's own, and silently discarding it on a network blip would be worse
    # than stopping.
    if ! status=$(devin-cli auth status 2>&1); then
        echo "Failed to read Devin authentication status." >&2
        exit 1
    fi
    if [[ "${status,,}" == *"failed to fetch"* ]]; then
        echo "Failed to validate Devin authentication." >&2
        exit 1
    fi
    [[ "${status,,}" == *"not logged in"* ]] && login_required=true
fi

if [[ "${login_required}" == true ]]; then
    echo "Not authenticated. Starting Devin login..."
    # An empty key reads as logged-in to the CLI, so `auth login` would refuse
    # to run. Clearing the session first is what makes the login below
    # reachable from that state.
    if [[ "${state}" == empty ]] && ! devin-cli auth logout >/dev/null 2>&1; then
        echo "Failed to clear empty Devin credentials." >&2
        exit 1
    fi
    # No browser runs in the sandbox, so the default localhost redirect never
    # comes back. --force-manual-token-flow is Devin's own answer for that
    # case, documented for remote and SSH sessions: it prints a URL to open on
    # the host and reads the token back here.
    if ! devin-cli auth login --force-manual-token-flow; then
        echo "Login failed." >&2
        exit 1
    fi
    # Validate the durable key before launching the agent, matching the base
    # Devin wrapper. The enterprise key stays on disk after validation.
    if ! status=$(devin-cli auth status 2>&1) ||
        [[ "${status,,}" == *"failed to fetch"* ]] ||
        [[ "${status,,}" == *"not logged in"* ]]; then
        echo "Failed to validate Devin login." >&2
        exit 1
    fi
fi

# exec so devin-cli replaces this wrapper rather than running underneath it:
# Ctrl-C and SIGTERM then reach the CLI directly instead of a shell that would
# have to forward them.
exec devin-cli "$@"
