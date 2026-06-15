# syntax=docker/dockerfile:1.7
# NanoClaw sandbox image.
#
# Everything needed to run NanoClaw is pre-baked so sandbox creation is
# fast: the kit (spec.yaml) only applies policy — network rules, credential
# proxying, published ports — and the entrypoint starts the pre-built
# service. This replaces the previous flow that cloned, pnpm-installed,
# tsc-built, and docker-built the agent image at first boot (5-12 minutes).
#
# Build with scripts/build-image.sh. The inner container images
# (nanoclaw-agent, OneCLI gateway, postgres) are NOT embedded here — they
# are pulled by digest from their registries on first boot (see
# scripts/seed-images.sh). This image only bakes the digest-pinned pin
# list those pulls read.

FROM docker/sandbox-templates:claude-code-docker

ARG NANOCLAW_REPO=https://github.com/nanocoai/nanoclaw.git
ARG NANOCLAW_REF=main
# Keep in lockstep with package.json `packageManager` in the nanoclaw repo.
ARG PNPM_VERSION=10.33.0

USER root
# Node 22 (nanoclaw requires >=20, pnpm v10 requires >=22) and pnpm.
RUN npm install -g n && n 22 && npm install -g "pnpm@${PNPM_VERSION}"
# OneCLI installs its CLI into ~/.local/bin; keep it on PATH in every shell
# context the sandbox runtime spawns.
RUN echo 'export PATH="/home/agent/.local/bin:$PATH"' >> /etc/sandbox-persistent.sh

USER agent
WORKDIR /home/agent
# Full clone (not --depth 1): nanoclaw's /add-<channel> skills fetch the
# upstream `channels` and `providers` branches at runtime.
RUN git clone "${NANOCLAW_REPO}" nanoclaw && \
    cd nanoclaw && \
    git checkout --quiet "${NANOCLAW_REF}" && \
    pnpm install --network-concurrency=1 && \
    pnpm rebuild better-sqlite3 && \
    pnpm run build

# Stamp nanoclaw's upgrade state: the image bake is the install (deps +
# build are done), and without the recorded version the service's upgrade
# tripwire refuses to start (docs/upgrade-recovery.md upstream).
RUN cd nanoclaw && pnpm exec tsx scripts/upgrade-state.ts set

# OneCLI CLI binary. The gateway itself (onecli + postgres containers) is
# pulled into the inner Docker daemon by seed-images.sh at first boot.
RUN curl -fsSL https://onecli.sh/cli/install | sh && \
    /home/agent/.local/bin/onecli version

USER root
COPY --chmod=0755 scripts/start-nanoclaw.sh /usr/local/bin/nanoclaw-start
COPY --chmod=0755 scripts/seed-images.sh /usr/local/bin/nanoclaw-seed-images
# Launcher for manual invocation (sbx exec <sandbox> nanoclaw ...).
RUN printf '#!/bin/sh\ncd /home/agent/nanoclaw\nexec node dist/index.js "$@"\n' > /usr/local/bin/nanoclaw && \
    chmod 0755 /usr/local/bin/nanoclaw

# Digest-pinned pin list for the inner images seed-images.sh pulls on first
# boot, one entry per line: "<pull-ref> <local-tag>". The pull ref should be
# digest-pinned (CI passes <image>@sha256:...); the local tag is the name
# NanoClaw/OneCLI expect (e.g. CONTAINER_IMAGE resolves nanoclaw-agent:latest,
# and the gateway/db tags must match nanoclaw's setup/onecli.ts).
# Defaults are tag-based for local dev; release builds override the *_IMAGE
# pull refs with digests while keeping the *_TAG local names unchanged.
ARG AGENT_IMAGE=nanoclaw-agent:latest
ARG AGENT_TAG=nanoclaw-agent:latest
ARG ONECLI_IMAGE=ghcr.io/onecli/onecli:1.23.0
ARG ONECLI_TAG=ghcr.io/onecli/onecli:1.23.0
ARG POSTGRES_IMAGE=postgres:18-alpine
ARG POSTGRES_TAG=postgres:18-alpine
RUN install -d -m 0755 /opt/nanoclaw && \
    { \
      echo "${AGENT_IMAGE} ${AGENT_TAG}"; \
      echo "${ONECLI_IMAGE} ${ONECLI_TAG}"; \
      echo "${POSTGRES_IMAGE} ${POSTGRES_TAG}"; \
    } > /opt/nanoclaw/inner-images.txt

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/nanoclaw-start"]
