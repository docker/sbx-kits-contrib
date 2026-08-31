# syntax=docker/dockerfile:1.7
# Paperclip sandbox image.
#
# Paperclip is a Node.js server + React UI that orchestrates a team of AI
# agents ("if OpenClaw is an employee, Paperclip is the company"). Agent
# CLIs run as child processes in the same container — no Docker-in-Docker
# — so the whole install pre-bakes into one image: the pinned paperclipai
# CLI (which carries @paperclipai/server and the built UI; its bundled
# embedded-postgres binaries are swapped for distro PostgreSQL below),
# running on the claude-code template so the claude_local adapter has
# Claude Code available.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# kiro/copilot.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL near
# the end of this file would expand to an empty string.
ARG BASE_IMAGE

# Calendar versioning upstream (vYYYY.MDD.P). Pin deliberately.
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

CMD ["/usr/local/bin/paperclip-start"]
