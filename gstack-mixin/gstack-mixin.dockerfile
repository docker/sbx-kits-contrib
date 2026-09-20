# syntax=docker/dockerfile:1.7
# Overlay recipe for the gstack mixin.
#
# Nothing here can be redirected with a --prefix: `./setup` registers every
# slash command as an ABSOLUTE symlink into the install path, Playwright bakes
# its browser path, and the rest arrives through apt. So this takes the shape
# the guide prescribes for an unrelocatable install — the workload's own base
# as a build stage, the unmodified install run on it, and only the specific
# resulting paths copied into a scratch overlay.
#
# The build stage installs at /home/agent, the sandbox runtime's own home, for
# the same reason the workload does: path and user must match the runtime or
# every registered symlink dangles.
ARG BASE_IMAGE=docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE} AS build

ARG GSTACK_REF=a5833c413f98b13f105beac96262e8098b628461
ARG BUN_VERSION=1.3.10

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering).
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Bun to /usr/local so the agent user can run it (upstream CI does the same).
RUN curl -fsSL --retry 5 https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}"

# Chromium + system deps for the browse daemon. Run unmodified — see the
# COPY set at the bottom for which parts of the result can honestly travel.
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
# Keep .git — /gstack-upgrade and the version stamp use it.
RUN git clone https://github.com/garrytan/gstack.git /home/agent/.claude/skills/gstack && \
    git -C /home/agent/.claude/skills/gstack checkout --quiet "${GSTACK_REF}"

# Builds the Bun binaries, registers every skill under ~/.claude/skills,
# creates ~/.gstack state.
RUN cd /home/agent/.claude/skills/gstack && \
    GSTACK_SKIP_FONTS=1 GSTACK_PLAN_TUNE_HOOKS=no ./setup --no-prefix

USER root
# v2's environment.variables. A mixin's image config is not the composed
# image's, so ENV would be dropped at assembly — the exports ride the overlay
# instead, sourced by the base workload's login shell.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/gstack-env.sh <<'EOF'
export GSTACK_PLAN_TUNE_HOOKS=no
export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
EOF

# The specific resulting paths, and only those.
#
# What travels: Bun's binaries, the Chromium bundle Playwright downloaded, the
# font packages (self-contained data under /usr/share, plus fontconfig's
# rendered cache), and the registered skill pack at the agent's home.
#
# What deliberately does NOT: the shared libraries `playwright install
# --with-deps` apt-installed for Chromium. Those are ABI-coupled to the
# distribution they came from and are tracked in its dpkg database; copying a
# subset of one base's /usr/lib onto an unknown base would both break the
# receiving system's package state and risk a loader mismatch. The consequence
# is stated rather than papered over: /browse works when the composed base is
# an Ubuntu sandbox template (the family this build stage comes from, which
# already carries them), and fails closed elsewhere while every other slash
# command keeps working. The alternative — an install hook apt-installing them
# on the composed base — would need a package manager, node, and a new
# install-phase egress grant that v2 never asked for.
RUN set -eux; \
    mkdir -p /out/usr/local/bin /out/opt /out/home/agent /out/usr/share /out/etc; \
    cp -a /usr/local/bin/bun /out/usr/local/bin/bun; \
    [ -e /usr/local/bin/bunx ] && cp -a /usr/local/bin/bunx /out/usr/local/bin/bunx || true; \
    cp -a /opt/playwright-browsers /out/opt/playwright-browsers; \
    cp -a /home/agent/.claude /out/home/agent/.claude; \
    [ -d /home/agent/.gstack ] && cp -a /home/agent/.gstack /out/home/agent/.gstack || true; \
    cp -a /usr/share/fonts /out/usr/share/fonts; \
    cp -a /etc/fonts /out/etc/fonts; \
    chown -R 1000:1000 /out/home/agent; \
    test -d /out/home/agent/.claude/skills/gstack

# The overlay: the skill pack, Bun, the browser bundle and the fonts, landing
# on any base. No ENTRYPOINT — the base workload's launch command stays, and
# the user runs `claude` from the shell.
FROM scratch
COPY --from=build /out /
