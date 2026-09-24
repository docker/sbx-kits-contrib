# syntax=docker/dockerfile:1
# v2's sandbox.image, carried over verbatim. shell-docker provides uv, bash,
# git, a CA store, and the uid-1000 agent user required by sbx@1. Its Node 22
# is below Agent Canvas' current >=24 engine floor, so Node 24 is installed
# before the package.
FROM docker/sandbox-templates:shell-docker

ARG AGENT_CANVAS_VERSION
ARG OPENHANDS_VERSION

# The former root install hooks are immutable image content in v3. The npm
# package and the descriptor share one version pin. `n 24` follows the
# supported major while the package release itself is exact.
USER root
RUN set -eux; \
    [ -n "$AGENT_CANVAS_VERSION" ]; \
    npm install -g n; \
    n 24; \
    i=0; \
    while [ "$i" -lt 3 ]; do \
      i=$((i+1)); \
      if npm install -g --prefix /usr/local "@openhands/agent-canvas@${AGENT_CANVAS_VERSION}" \
          --no-audit --no-fund --maxsockets 3 --fetch-retries 5 \
          --fetch-retry-maxtimeout 120000; then \
        break; \
      fi; \
      if [ "$i" -ge 3 ]; then \
        echo "npm install failed after $i attempts" >&2; \
        exit 1; \
      fi; \
      echo "npm attempt $i failed; retrying in 5s" >&2; \
      sleep 5; \
    done; \
    installed="$(node -p 'require("/usr/local/lib/node_modules/@openhands/agent-canvas/package.json").version')"; \
    [ "$installed" = "$AGENT_CANVAS_VERSION" ]

# shell-docker's uv has no working uvx. Agent Canvas invokes
# `uvx --from openhands-agent-server==<ver> agent-server`; `uv tool run`
# supports that interface.
RUN <<'EOF'
cat > /usr/local/bin/uvx <<'SCRIPT'
#!/bin/sh
exec uv tool run "$@"
SCRIPT
chmod 0755 /usr/local/bin/uvx
EOF

# The headless OpenHands runner was installed by v2 as uid 1000.
USER agent
RUN set -eux; \
    [ -n "$OPENHANDS_VERSION" ]; \
    uv tool install --python 3.12 "openhands==${OPENHANDS_VERSION}"; \
    "$HOME/.local/bin/openhands" --version

# v2's launcher, promoted from a create-time hook into the image.
USER root
RUN <<'EOF'
cat > /usr/local/bin/openhands-canvas-launch <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-8000}"; BASE="http://localhost:${PORT}"
agent-canvas --port "$PORT" & SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' INT TERM EXIT
for _ in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BASE/health" 2>/dev/null)" = "200" ] && break
  sleep 2
done
KEY="$(cat "$HOME/.openhands/agent-canvas/api-key.txt" 2>/dev/null | tr -d '\r\n' || true)"
curl -s -X PATCH "$BASE/api/settings" -H "X-Session-API-Key: $KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"agent_settings_diff\":{\"llm\":{\"model\":\"${LLM_MODEL}\",\"api_key\":\"sbx-proxy-managed\"}}}" \
  >/dev/null 2>&1 || echo "note: set the model in Settings > LLM if the UI is not preconfigured" >&2
echo "Agent Canvas is running at ${BASE} (forward with 'sbx run -p ${PORT} …')"
wait "$SRV"
SCRIPT
chmod 0755 /usr/local/bin/openhands-canvas-launch
EOF

# v2's environment.variables, now in the OCI image-config slot they belong in.
# HTTP_PROXY/HTTPS_PROXY deliberately remain inherited: that is how credential
# injection and egress control work.
ENV LLM_MODEL="anthropic/claude-opus-4-8" \
    PORT="8000" \
    OPENHANDS_SUPPRESS_BANNER="1" \
    OH_SECRET_KEY="sbx-openhands-dev" \
    NO_PROXY="localhost,127.0.0.1,host.docker.internal" \
    no_proxy="localhost,127.0.0.1,host.docker.internal"

# Restate the runtime identity and workspace rather than relying on inherited
# image config; sbx@1 requires a non-empty resolvable user.
USER agent
WORKDIR /home/agent/workspace
ENTRYPOINT ["/usr/local/bin/openhands-canvas-launch"]
