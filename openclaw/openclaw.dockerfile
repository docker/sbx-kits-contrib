# syntax=docker/dockerfile:1.7
# Content for the `openclaw` workload kit.
#
# Everything needed to run OpenClaw is pre-baked so sandbox creation is
# fast: Node 22, the pinned openclaw npm package, Chromium for the browser
# tool (saves the 60-90s playwright download on first browser use), and a
# minimal gateway config. The descriptor only applies policy; the entrypoint
# waits for the gateway then drops into `openclaw chat`.
#
# MIGRATION NOTE: this was v2's Dockerfile, built by CI into
# docker.io/sbx/openclaw-image:latest and named back from spec.yaml's
# `sandbox.image`. In v3 the recipe is the kit's content directly, so the
# published-tag round trip is gone. The base is v2's default, verbatim.

# Parameterised rather than hard-coded so a build can be aimed at a specific
# base digest without editing this file. Nothing in this repository passes the
# arg, so the default is what ships -- and it is the same tag this image has
# always been built on. Unlike OPENCLAW_VERSION below, the base is left
# floating on purpose, so a nightly rebuild picks up template fixes.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# Date-based upstream versioning; releases are ~daily. Pin deliberately.
#
# MIGRATION NOTE: the pin is no longer defaulted here. It is the kit's
# `args.version`, handed in as this build arg, so one declaration is validated
# against its pattern, published in `provides`, and installed -- v2's bare ARG
# was none of those things.
ARG OPENCLAW_VERSION

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

# Startup hooks run with a minimal PATH that may not include the npm
# global bin dir — pin the binary somewhere always on PATH.
RUN ln -sf "$(npm prefix -g)/bin/openclaw" /usr/local/bin/openclaw

COPY --chmod=0755 files/home/.local/bin/openclaw-start.sh /usr/local/bin/openclaw-start

USER agent
WORKDIR /home/agent
# Minimal config so the gateway starts in configured local mode (no
# --allow-unconfigured escape hatch needed). Strictly validated upstream —
# keep this tiny. The fuller kit-shipped config lands over it below.
RUN mkdir -p /home/agent/.openclaw && \
    printf '{\n  "gateway": {\n    "mode": "local"\n  }\n}\n' > /home/agent/.openclaw/openclaw.json

# MIGRATION NOTE: v2 shipped the files/ tree as kit content that the artifact
# loader staged into the sandbox at create -- which is why the entrypoint and
# the startup hook name paths under /home/agent rather than the image copy
# above, and why the fuller openclaw.json (model, nested-sandbox backend,
# gateway port and bind) overwrote the minimal one seeded a moment ago. In v3
# the kit and the image are one artifact, so "kit content that is not image
# content" has no meaning: the tree is copied in here, at the same in-image
# paths and in the same order, so the end state is unchanged. The 0644 the
# loader produced is preserved deliberately -- both scripts are invoked
# through `sh` for exactly that reason, and changing the mode would leave two
# places disagreeing about why.
COPY --chown=agent:agent files/home/ /home/agent/

USER root
# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# MIGRATION NOTE: this stays a label. It is not a v3 capability -- the grammar
# has no Docker-in-Docker request, and `privileged@1` is a different (larger)
# ask that this kit never made.
LABEL com.docker.sandboxes.start-docker="true"

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image.
#
# Overriding `flavor` is not optional. sbx reads it as an agent identifier: it
# surfaces the value as an image's `Agent`, and uses it to warn when a template
# looks built for a different agent than the one being run. Left inherited it
# reads "shell-docker", so sbx reports this image's agent as the base template
# rather than OpenClaw. It must be the kit name exactly: `openclaw`.
LABEL com.docker.sandboxes.flavor="openclaw"

# Informational only -- nothing in sbx reads this. Worth setting because it is
# the one place the produced image itself records what it was built on: the
# default tag above, or whatever a build passed instead.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here -- nothing reads it, and this
# image is not part of that template family, so it is left alone rather than
# asserted.

# v2's environment.variables, in the slot OCI already owns for static env.
# PLAYWRIGHT_BROWSERS_PATH is already set above, where the browser install
# needs it; OPENCLAW_STATE_DIR is declared here and read by the startup hook,
# which names it in its `env:` list.
ENV OPENCLAW_STATE_DIR=/home/agent/.openclaw

USER agent
WORKDIR /home/agent
# v2's sandbox.entrypoint: kit content, not the image binary, because the
# launch has to source the OAuth env file the gateway bootstrap writes.
#
# MIGRATION NOTE: v2's `CMD ["/usr/local/bin/openclaw-start"]` is dropped
# rather than kept beside it -- the launch argv is Entrypoint + Cmd
# (SPEC-v3 §8), so leaving the CMD in place would append its path to every
# launch as a positional argument.
ENTRYPOINT ["sh", "/home/agent/.local/bin/openclaw-start.sh"]
