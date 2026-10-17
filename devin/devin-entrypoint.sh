#!/bin/bash
#
# The launcher the sandbox entrypoint resolves as `devin`; the real CLI is
# installed alongside it as `devin-cli`.
#
# Devin CLI authenticates from ~/.local/share/devin/credentials.toml. Two
# things have to happen before the agent starts, and neither can be expressed
# declaratively in spec.yaml:
#
#   1. When the sandbox has no reusable credential, Devin's own login flow has
#      to run — there is no way to provision this credential from the host
#      ahead of time, because the durable key only exists once an account has
#      signed in.
#   2. Whatever key that login leaves on disk has to be replaced with the
#      proxy's placeholder before the agent runs, so the container never holds
#      a usable credential. The proxy substitutes the real, host-held key on
#      Devin egress.
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
#   sentinel   — already the proxy placeholder: a credential the host holds
#   credential — a real key sitting in the container, which must not stay
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

# Replace any real key on disk with the proxy placeholder, then prove the
# result still authenticates. The proof is the point: by the time this runs
# the proxy has had its chance to capture the real key, and if it did not, the
# placeholder would leave the session silently unauthenticated. Deleting the
# file on that outcome sends the next launch back through login rather than
# into a confusing half-authenticated state.
secure_credentials() {
    # Declared separately from the assignments below on purpose. `local x=$(…)`
    # returns `local`'s own status, not the command's, so `! local status=$(…)`
    # can never see a failure.
    local status

    # A bare `return` propagates the failing test's status, so an anomalous
    # state here — reaching the agent with no credential file at all, after a
    # login that reported success — is a hard failure rather than a silent
    # pass. That is the right direction: the alternative is starting the agent
    # with nothing to authenticate with.
    [[ -f "${credentials_file}" ]] || return
    grep -Eq '^[[:space:]]*windsurf_api_key[[:space:]]*=' "${credentials_file}" || return

    # Already the placeholder: nothing to rewrite, and re-validating would
    # spend a round trip on every single container start.
    grep -Fqx 'windsurf_api_key = "devin-proxy-managed"' "${credentials_file}" && return 0

    # sed's own status is not checked because the grep immediately below is a
    # stronger check of the same thing: it reads back what sed was supposed to
    # have written.
    sed -i 's/^[[:space:]]*windsurf_api_key[[:space:]]*=.*$/windsurf_api_key = "devin-proxy-managed"/' "${credentials_file}"
    if ! grep -Fqx 'windsurf_api_key = "devin-proxy-managed"' "${credentials_file}" ||
        ! status=$(devin-cli auth status 2>&1) ||
        [[ "${status,,}" == *"failed to fetch"* ]] ||
        [[ "${status,,}" == *"not logged in"* ]]; then
        rm -f "${credentials_file}"
        return 1
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
    # Login returns as soon as it has written the durable key. This status
    # call is what puts that key on the wire to a Devin host, which is the
    # moment the proxy can capture it — before secure_credentials below
    # replaces the local copy.
    if ! status=$(devin-cli auth status 2>&1) ||
        [[ "${status,,}" == *"failed to fetch"* ]] ||
        [[ "${status,,}" == *"not logged in"* ]]; then
        echo "Failed to validate Devin login." >&2
        exit 1
    fi
fi

if ! secure_credentials; then
    echo "Failed to secure Devin credentials." >&2
    exit 1
fi

# exec so devin-cli replaces this wrapper rather than running underneath it:
# Ctrl-C and SIGTERM then reach the CLI directly instead of a shell that would
# have to forward them.
exec devin-cli "$@"
