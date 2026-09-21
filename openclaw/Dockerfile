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

# Parameterised rather than hard-coded so a build can be aimed at a specific
# base digest without editing this file. Nothing in this repository passes the
# arg, so the default is what ships -- and it is the same tag this image has
# always been built on. Unlike OPENCLAW_VERSION below, the base is left
# floating on purpose, so the shared pipeline's nightly rebuild picks up
# template fixes.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

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

COPY --chmod=0755 files/home/.local/bin/openclaw-start.sh /usr/local/bin/openclaw-start

USER agent
WORKDIR /home/agent
# Minimal config so the gateway starts in configured local mode (no
# --allow-unconfigured escape hatch needed). Strictly validated upstream —
# keep this tiny.
RUN mkdir -p /home/agent/.openclaw && \
    printf '{\n  "gateway": {\n    "mode": "local"\n  }\n}\n' > /home/agent/.openclaw/openclaw.json

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
LABEL com.docker.sandboxes.start-docker="true"

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image.
#
# Overriding `flavor` is not optional. sbx reads it as an agent identifier: it
# surfaces the value as an image's `Agent`, and uses it to warn when a template
# looks built for a different agent than the one being run. Left inherited it
# reads "shell-docker", so sbx reports this image's agent as the base template
# rather than OpenClaw. It must be the kit name exactly as spec.yaml uses it:
# `openclaw`.
LABEL com.docker.sandboxes.flavor="openclaw"

# Informational only -- nothing in sbx reads this. Worth setting because it is
# the one place the produced image itself records what it was built on: the
# default tag above, or whatever a build passed instead.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here -- nothing reads it, and this
# image is not part of that template family, so it is left alone rather than
# asserted.

CMD ["/usr/local/bin/openclaw-start"]
