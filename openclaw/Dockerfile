# syntax=docker/dockerfile:1.7
# OpenClaw sandbox image.
#
# Everything needed to run OpenClaw is pre-baked so sandbox creation is
# fast: Node 22, the pinned openclaw npm package, Chromium for the browser
# tool (saves the 60-90s playwright download on first browser use), and a
# minimal gateway config. The kit (spec.yaml) only applies policy and the
# entrypoint waits for the gateway then drops into `openclaw chat`.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# kiro/copilot.

FROM docker/sandbox-templates:shell-docker

# Date-based upstream versioning; releases are ~daily. Pin deliberately.
ARG OPENCLAW_VERSION=2026.6.5

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering); the
# Ubuntu archives all support HTTPS.
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Node 22 (openclaw requires >= 22.19) and the pinned openclaw package.
# The package's postinstall is offline-safe (local plugin fixups only).
RUN npm install -g n && n 22 && npm install -g "openclaw@${OPENCLAW_VERSION}"

# Chromium + headless deps for openclaw's browser tool, shared system-wide.
# `install --with-deps` apt-installs the runtime libraries; the browser
# download itself goes to PLAYWRIGHT_BROWSERS_PATH below. Playwright 1.60
# has no dependency map for the template's Ubuntu 26.04 yet — override the
# host platform to 24.04 (same t64 package naming era) so the install
# proceeds.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends xvfb && \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    PW_ARCH=$([ "$ARCH" = "amd64" ] && echo x64 || echo arm64) && \
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE="ubuntu24.04-$PW_ARCH" \
      node "$(npm root -g)/openclaw/node_modules/playwright-core/cli.js" install --with-deps chromium && \
    chmod -R a+rX /opt/ms-playwright && \
    rm -rf /var/lib/apt/lists/*

# Startup commands run with a minimal PATH that may not include the npm
# global bin dir — pin the binary somewhere always on PATH.
RUN ln -sf "$(npm prefix -g)/bin/openclaw" /usr/local/bin/openclaw

COPY --chmod=0755 scripts/start-openclaw.sh /usr/local/bin/openclaw-start

USER agent
WORKDIR /home/agent
# Minimal config so the gateway starts in configured local mode (no
# --allow-unconfigured escape hatch needed). Strictly validated upstream —
# keep this tiny.
RUN mkdir -p /home/agent/.openclaw && \
    printf '{\n  "gateway": {\n    "mode": "local"\n  }\n}\n' > /home/agent/.openclaw/openclaw.json

CMD ["/usr/local/bin/openclaw-start"]
