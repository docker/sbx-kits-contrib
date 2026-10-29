#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
launcher="$root/../../bin/agentmemory-sbx"
exec 9>"$root/start.lock"
flock -w 120 9

ready() {
  curl --noproxy '*' --fail --silent --max-time 2 \
    http://127.0.0.1:3111/agentmemory/livez 2>/dev/null | node -e '
      let body = "";
      process.stdin.on("data", chunk => body += chunk);
      process.stdin.on("end", () => {
        try {
          const value = JSON.parse(body);
          process.exit(value.service === "agentmemory" && value.status === "ok" &&
            (typeof value.viewerPort === "number" || value.viewerSkipped === true) ? 0 : 1);
        } catch { process.exit(1); }
      });
    '
}

if ready; then
  exit 0
fi

nohup sh "$launcher" --verbose >"$root/startup.log" 2>&1 </dev/null 9>&- &
attempt=0
while [ "$attempt" -lt 90 ]; do
  if ready; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "agentmemory did not become ready. See $root/startup.log" >&2
exit 1
