#!/bin/sh
set -eu

opt=/opt/agentmemory-sbx
state=/home/agent/.local/share/agentmemory-sbx

umask 077
mkdir -p "$state"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$state/start.lock"
  flock -w 120 9
fi

ready() {
  env -u NODE_USE_ENV_PROXY "$opt/node/bin/node" -e '
    fetch("http://127.0.0.1:3111/agentmemory/livez", { signal: AbortSignal.timeout(2000) })
      .then(response => response.ok ? response.json() : null)
      .then(
        value => process.exit(value && value.service === "agentmemory" && value.status === "ok" ? 0 : 1),
        () => process.exit(1),
      );
  '
}

if ready; then
  exit 0
fi

nohup sh /usr/local/bin/agentmemory-sbx --verbose >"$state/startup.log" 2>&1 </dev/null 9>&- &
attempt=0
while [ "$attempt" -lt 120 ]; do
  if ready; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "agentmemory did not become ready. See $state/startup.log" >&2
exit 1
