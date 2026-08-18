# syntax=docker/dockerfile:1.7
# gstack sandbox image.
#
# gstack is a Claude Code skill pack (23 slash commands: /ship, /review,
# /qa, /browse, ...) plus compiled Bun binaries, including a headless
# Chromium browse daemon. This image pre-bakes the full install — Bun,
# the gstack checkout @ pinned SHA with its setup run, and Chromium —
# on the claude-code template, so a sandbox attaches straight into a
# Claude Code session with all skills registered.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# kiro/copilot.

FROM docker/sandbox-templates:claude-code

# gstack has no release tags; pin a commit SHA (VERSION 1.57.10.0).
ARG GSTACK_REF=a5833c413f98b13f105beac96262e8098b628461
ARG BUN_VERSION=1.3.10

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering).
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Bun to /usr/local so the agent user can run it (upstream CI does the same).
RUN curl -fsSL --retry 5 https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}"

# Chromium + system deps for the browse daemon, shared system-wide.
# Playwright has no dependency map for the template's Ubuntu 26.04 yet —
# override the host platform to 24.04 (same t64 package naming era).
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
ARG TARGETARCH
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fonts-liberation fonts-noto-color-emoji fontconfig xvfb x11-utils && \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    PW_ARCH=$([ "$ARCH" = "amd64" ] && echo x64 || echo arm64) && \
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE="ubuntu24.04-$PW_ARCH" \
      npx -y playwright@1.58.2 install --with-deps chromium && \
    chmod -R a+rX /opt/playwright-browsers && \
    fc-cache -f && \
    rm -rf /var/lib/apt/lists/*

USER agent
WORKDIR /home/agent
# Clone at the runtime user's final $HOME path: setup registers skills via
# absolute symlinks into the install path, so path and user must match the
# sandbox runtime. Keep .git — /gstack-upgrade and the version stamp use it.
RUN git clone https://github.com/garrytan/gstack.git /home/agent/.claude/skills/gstack && \
    git -C /home/agent/.claude/skills/gstack checkout --quiet "${GSTACK_REF}"

# Run setup non-interactively: builds the Bun binaries, registers every
# skill under ~/.claude/skills, creates ~/.gstack state. Fonts are already
# installed above; plan-tune hooks stay off for a predictable headless
# baseline (users can enable later with `./setup`).
RUN cd /home/agent/.claude/skills/gstack && \
    GSTACK_SKIP_FONTS=1 GSTACK_PLAN_TUNE_HOOKS=no ./setup --no-prefix

CMD ["claude"]
