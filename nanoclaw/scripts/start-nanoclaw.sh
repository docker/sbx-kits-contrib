#!/bin/sh
# NanoClaw sandbox entrypoint.
#
# Everything heavy (nanoclaw checkout, node_modules, compiled dist/, agent
# container image, OneCLI gateway images) is pre-baked into the sandbox
# image, so this script only:
#   1. restores docker socket perms (sbx restarts the inner daemon each
#      boot, resetting them),
#   2. seeds the inner Docker daemon by pulling the inner images from their
#      registries (first boot only),
#   3. starts the NanoClaw service if it isn't running,
#   4. hands the terminal to the setup wizard.

sudo -n chmod 666 /var/run/docker.sock 2>/dev/null || true

/usr/local/bin/nanoclaw-seed-images || exit 1

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

export PATH="$HOME/.local/bin:$PATH"
# container build + service registration are pre-baked into the image /
# not applicable inside a sandbox; the wizard still drives OneCLI install,
# auth, CLI agent creation, timezone, and channel pairing.
exec env NANOCLAW_SKIP=service,container npm run --silent setup:auto
