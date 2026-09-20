# syntax=docker/dockerfile:1.7
# The paperclip workload's content. This is the v2 kit's Dockerfile: v2
# published it as docker.io/sbx/paperclip-image:latest and pointed
# `sandbox.image` at the result, while a v3 workload's layers *are* the root
# filesystem -- so the intermediate publish disappears and this recipe builds
# the kit directly. v2's environment.variables and sandbox.entrypoint land at
# the bottom, in the image config that already owns runtime config.
#
# Paperclip is a Node.js server + React UI that orchestrates a team of AI
# agents ("if OpenClaw is an employee, Paperclip is the company"). Agent
# CLIs run as child processes in the same container — no Docker-in-Docker
# — so the whole install pre-bakes into the image: the pinned paperclipai
# CLI (which carries @paperclipai/server and the built UI; its bundled
# embedded-postgres binaries are swapped for distro PostgreSQL below),
# running on the claude-code template so the claude_local adapter has
# Claude Code available.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL near
# the end of this file would expand to an empty string.
ARG BASE_IMAGE

# The kit's `version` arg, handed here as a build arg. The default is
# restated so a plain `docker build` of this directory still works.
ARG PAPERCLIP_VERSION=2026.609.0

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering).
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Node 22 (paperclip requires >=20; its own agent images use 22) and the
# pinned paperclipai CLI. The install pulls @paperclipai/server, the
# built UI, embedded-postgres platform binaries, and sharp prebuilds.
# `n 22` floats to the latest 22.x patch intentionally (security fixes);
# the shared kit-image pipeline's nightly rebuild catches any drift.
RUN npm install -g n && n 22 && npm install -g "paperclipai@${PAPERCLIP_VERSION}"

# Pin the binary somewhere always on PATH (startup commands and
# entrypoints run with a minimal PATH).
RUN ln -sf "$(npm prefix -g)/bin/paperclipai" /usr/local/bin/paperclipai

# Distro PostgreSQL instead of paperclip's embedded-postgres: the bundled
# arm64 binaries are linked for 4KB pages and fail to load on the sandbox
# microVM's 16KB-page kernel ("ELF load command address/offset not
# page-aligned"). Ubuntu's builds are page-size agnostic. The entrypoint
# init's a cluster under PAPERCLIP_HOME and exports DATABASE_URL.
RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 scripts/start-paperclip.sh /usr/local/bin/paperclip-start

# The kit's files/home/ tree. v2's artifact loader copied it into /home/agent/
# at sandbox create; v3 has no implicit files/ convention, so the recipe lands
# it. --chmod=0644 reproduces the mode the loader left, which is why the
# ENTRYPOINT below invokes the wrapper through `sh` rather than exec'ing it --
# keeping v2's sandbox.entrypoint spelling exactly.
COPY --chown=agent:agent --chmod=0644 \
     files/home/.local/bin/paperclip-start.sh \
     files/home/.local/bin/paperclip-anthropic-auth.sh \
     /home/agent/.local/bin/

USER agent
WORKDIR /home/agent
# State root for config, embedded postgres data, assets, secrets.
RUN mkdir -p /home/agent/.paperclip

# This OVERRIDES the value inherited from the base image, which describes the
# base rather than this image. Overriding is not optional: left inherited it
# would read "claude-code", and sbx would report this image's agent as
# "claude-code" instead of "paperclip".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the
# value as an image's `Agent` in the API. So it must be the kit's own name:
# `paperclip`.
LABEL com.docker.sandboxes.flavor="paperclip"

# Informational only — nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
ENV HOST=0.0.0.0 \
    PAPERCLIP_BIND=lan \
    PAPERCLIP_DEPLOYMENT_MODE=authenticated \
    PAPERCLIP_HOME=/home/agent/.paperclip \
    PAPERCLIP_TELEMETRY_DISABLED=1 \
    SERVE_UI=true

# v2's sandbox.entrypoint. Kit content wrapping the image-baked start script:
# the entrypoint has to source the Anthropic auth env file the startup hook
# writes. Setting ENTRYPOINT also clears the CMD inherited from the base
# (and replaces the v2 image's own CMD, which named the same start script),
# so nothing is appended to it.
ENTRYPOINT ["sh", "/home/agent/.local/bin/paperclip-start.sh"]
