#!/bin/bash
#
# Entry point the sandbox resolves as `devin`; the real CLI is `devin-cli`.
#
# Devin CLI authenticates from ~/.local/share/devin/credentials.toml. When sbx
# has no reusable credential to provision there, this wrapper starts Devin's
# own login flow before launching the agent.

set -uo pipefail

secure_credentials() {
    local credentials_file="${HOME}/.local/share/devin/credentials.toml"
    if [[ ! -f "${credentials_file}" ]] ||
        ! grep -Eq '^[[:space:]]*windsurf_api_key[[:space:]]*=' "${credentials_file}"; then
        return
    fi
    if ! sed -i 's/^[[:space:]]*windsurf_api_key[[:space:]]*=.*$/windsurf_api_key = "devin-proxy-managed"/' "${credentials_file}" ||
        ! grep -Fqx 'windsurf_api_key = "devin-proxy-managed"' "${credentials_file}"; then
        echo "Failed to secure Devin credentials." >&2
        return 1
    fi
}

credential_state() {
    local credentials_file="${HOME}/.local/share/devin/credentials.toml"
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

# `devin auth status` exits 0 whether or not a session exists, so its exit code
# cannot gate the login flow — the message it prints is the only signal.
#
# Captured into a variable rather than piped into grep on purpose: `grep -q`
# exits as soon as it matches, which can leave devin-cli killed by SIGPIPE, and
# under `pipefail` that failure becomes the pipeline's status and would mask a
# successful match.
state=$(credential_state)
login_required=false
if [[ "${state}" == absent || "${state}" == empty ]]; then
    login_required=true
elif [[ "${state}" != sentinel ]]; then
    if ! status=$(devin-cli auth status 2>&1); then
        echo "Failed to read Devin authentication status." >&2
        exit 1
    fi
    case "${status,,}" in
    *"not logged in"*) login_required=true ;;
    esac
fi

if [[ "${login_required}" == true ]]; then
    echo "Not authenticated. Starting Devin login..."
    if [[ "${state}" == empty ]] && ! devin-cli auth logout > /dev/null 2>&1; then
        echo "Failed to clear empty Devin credentials." >&2
        exit 1
    fi
    # No browser runs in the sandbox, so the default localhost redirect never
    # comes back. --force-manual-token-flow is Devin's own answer for that
    # case (documented for remote and SSH sessions): it prints a URL to open
    # on the host and reads the token back here.
    if ! devin-cli auth login --force-manual-token-flow; then
        echo "Login failed." >&2
        exit 1
    fi

    # Login returns after writing the durable key. Status validates that key
    # through GetUserStatus, which lets sandboxd persist it before the local
    # copy is replaced below.
    if ! status=$(devin-cli auth status 2>&1) ||
        [[ "${status,,}" == *"failed to fetch"* ]] ||
        [[ "${status,,}" == *"not logged in"* ]]; then
        echo "Failed to validate Devin login." >&2
        exit 1
    fi
fi

if ! secure_credentials; then
    exit 1
fi

# exec so devin-cli replaces this wrapper rather than running underneath it:
# Ctrl-C and SIGTERM then reach the CLI directly instead of a shell that would
# have to forward them.
exec devin-cli "$@"
