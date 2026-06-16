#!/bin/sh
# NanoClaw sandbox entrypoint.
#
# Everything heavy (nanoclaw checkout, node_modules, compiled dist/, agent
# container image, OneCLI CLI) is pre-baked into the sandbox image, so this
# script only:
#   1. restores docker socket perms (sbx restarts the inner daemon each
#      boot, resetting them),
#   2. seeds the inner Docker daemon by pulling the inner images from their
#      registries (first boot only),
#   3. bootstraps the OneCLI gateway (starts the compose stack, waits for
#      health, pre-registers the sandbox-injected Anthropic key),
#   4. starts the NanoClaw service if it isn't running,
#   5. hands the terminal to the setup wizard.

sudo -n chmod 666 /var/run/docker.sock 2>/dev/null || true

/usr/local/bin/nanoclaw-seed-images || exit 1

# --- OneCLI gateway bootstrap ---
# seed-images.sh has already pulled the onecli + postgres images into the
# inner daemon. Now start the gateway so setup:auto can take the
# non-interactive --remote-url path (NANOCLAW_ONECLI_API_HOST), and so we
# can pre-register the sandbox-injected Anthropic key before the auth step.
export PATH="$HOME/.local/bin:$PATH"
ONECLI_VERSION="${ONECLI_VERSION:-1.23.0}"

if ! curl -sf http://127.0.0.1:10254/api/health >/dev/null 2>&1; then
    echo "Starting OneCLI gateway..." >&2
    ONECLI_INSTALL_VERSION="$ONECLI_VERSION" sh -c "$(curl -fsSL https://onecli.sh/install)" \
        >/tmp/onecli-install.log 2>&1

    i=0
    until curl -sf http://127.0.0.1:10254/api/health >/dev/null 2>&1; do
        sleep 1
        i=$((i+1))
        if [ $i -ge 60 ]; then
            echo "Timed out waiting for OneCLI gateway" >&2
            cat /tmp/onecli-install.log >&2
            exit 1
        fi
    done
    echo "OneCLI gateway healthy." >&2
fi

# Pre-register the sandbox-injected Anthropic key (type=anthropic → x-api-key
# header, which is what api.anthropic.com requires). anthropicSecretExists()
# in setup/auto.ts will find it and skip the interactive auth picker.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    if ! onecli secrets list 2>/dev/null | grep -qi '"type":"anthropic"'; then
        echo "Pre-registering Anthropic key in OneCLI vault..." >&2
        onecli secrets create \
            --name Anthropic \
            --type anthropic \
            --value "$ANTHROPIC_API_KEY" \
            --host-pattern api.anthropic.com >/dev/null 2>&1 || true
    fi
fi
# --- end OneCLI gateway bootstrap ---

cd /home/agent/nanoclaw
mkdir -p logs data

if ! pgrep -f 'node dist/index\.js' >/dev/null 2>&1; then
    rm -f data/cli.sock
    node dist/index.js >> logs/nanoclaw.log 2>> logs/nanoclaw.error.log &
fi

echo "Starting NanoClaw service..." >&2
i=0
until [ -S data/cli.sock ]; do
    sleep 1
    i=$((i+1))
    if [ $i -ge 60 ]; then
        echo "Timed out after 60s waiting for data/cli.sock. Service logs follow:" >&2
        echo "--- nanoclaw.error.log ---" >&2
        cat logs/nanoclaw.error.log >&2 2>/dev/null
        echo "--- nanoclaw.log ---" >&2
        cat logs/nanoclaw.log >&2 2>/dev/null
        exit 1
    fi
done

# container build + service registration are pre-baked into the image /
# not applicable inside a sandbox; the wizard still drives OneCLI wiring
# (non-interactive via NANOCLAW_ONECLI_API_HOST), auth (skipped when the
# vault was pre-populated above), CLI agent creation, timezone, and channel
# pairing.
exec env NANOCLAW_SKIP=service,container \
         NANOCLAW_ONECLI_API_HOST=http://127.0.0.1:10254 \
         pnpm run --silent setup:auto
