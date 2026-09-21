# syntax=docker/dockerfile:1.7
# Content recipe for the `gstack` kit — the v2 Dockerfile, renamed to the stem
# gstack.dockerfile so the descriptor beside it finds it without a
# `dockerfile:` field.
#
# gstack is a Claude Code skill pack (slash commands: /ship, /review,
# /qa, /browse, ...) plus compiled Bun binaries, including a headless
# Chromium browse daemon. This image pre-bakes the full install — Bun,
# the gstack checkout @ pinned SHA with its setup run, and Chromium —
# on the claude-code template, so a sandbox attaches straight into a
# Claude Code session with all skills registered.
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

# All three are declared as kit args in gstack.yaml (`ref`, `version` and
# `bunVersion`, with buildArg: GSTACK_REF / GSTACK_VERSION / BUN_VERSION), so
# the frontend hands them in and the published descriptor records what was
# built. The defaults stay here so a plain `docker build` of this file still
# works.
#
# gstack has no release tags; pin a commit SHA. GSTACK_VERSION is upstream's
# own VERSION file at that commit, which is what the descriptor publishes as
# `gstack@<version>` — the checkout step below verifies the two agree rather
# than trusting this comment to keep them together.
ARG GSTACK_REF=a5833c413f98b13f105beac96262e8098b628461
ARG GSTACK_VERSION=1.57.10.0
ARG BUN_VERSION=1.3.10

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering).
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Bun to /usr/local so the agent user can run it (upstream CI does the same).
RUN curl -fsSL --retry 5 https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}"

# Chromium + system deps for the browse daemon, shared system-wide.
# Playwright has no dependency map for the template's Ubuntu 26.04 yet —
# override the host platform to 24.04 (same t64 package naming era).
#
# One of v2's two environment.variables, in the slot OCI already owns for
# static env — the v3 descriptor carries none. It was already set here in v2
# as well, because the build itself reads it.
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

# The pin's own check. `ref` is the authority and `version` is what the
# descriptor publishes, so the build is where they have to be reconciled: read
# upstream's VERSION out of the tree that was actually checked out and refuse
# to continue if it is not the version the descriptor claims. Bumping the SHA
# without bumping the version (or the reverse) fails here instead of shipping
# an image whose published provide describes a different commit.
RUN set -eu; \
    checked_out="$(cat /home/agent/.claude/skills/gstack/VERSION)"; \
    echo "gstack VERSION at ${GSTACK_REF}: ${checked_out}"; \
    [ "${checked_out}" = "${GSTACK_VERSION}" ] || { \
      echo "pin mismatch: descriptor says ${GSTACK_VERSION}, checkout ${GSTACK_REF} carries ${checked_out}" >&2; \
      exit 1; \
    }

# Run setup non-interactively: builds the Bun binaries, registers every
# skill under ~/.claude/skills, creates ~/.gstack state. Fonts are already
# installed above; plan-tune hooks stay off for a predictable headless
# baseline (users can enable later with `./setup`).
RUN cd /home/agent/.claude/skills/gstack && \
    GSTACK_SKIP_FONTS=1 GSTACK_PLAN_TUNE_HOOKS=no ./setup --no-prefix

# v2's second environment.variables entry. It was a spec.yaml declaration in
# v2 and is image config here, so the setting the agent sees at run time keeps
# matching the one the build above used.
ENV GSTACK_PLAN_TUNE_HOOKS=no

# This OVERRIDES the value inherited from the base image, which describes the
# base rather than this image. Overriding is not optional: left inherited it
# would read "claude-code", and sbx would report this image's agent as
# "claude-code" instead of "gstack".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the
# value as an image's `Agent` in the API. So it must be the kit's own name:
# `gstack`.
LABEL com.docker.sandboxes.flavor="gstack"

# Informational only — nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's `sandbox.entrypoint: [claude]`, in the slot OCI already owns for launch
# config. This replaces the v2 file's `CMD ["claude"]` rather than joining it:
# the launch argv is Entrypoint + Cmd, so keeping both would run
# `claude claude`.
ENTRYPOINT ["claude"]
