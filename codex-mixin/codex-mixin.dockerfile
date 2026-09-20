# syntax=docker/dockerfile:1

# Overlay recipe for the codex mixin: the same install the codex workload kit
# does, landed under /out and shipped as a `FROM scratch` delta that composes
# onto any base rather than as a root filesystem.
#
# The build stage is the workload's own base, verbatim. Two of the three things
# this recipe installs cannot be relocated by pointing an installer somewhere
# else — xdg-utils is an apt package, and apt owns where its files go — so the
# shape the guide prescribes applies: run the unmodified install on the
# workload's base, then copy the specific resulting paths into the overlay.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# xdg-utils, for the `xdg-open` that the BROWSER export below names. The
# package is one architecture-independent set of shell scripts with no
# dependencies once --no-install-recommends drops the X11 desktop-integration
# half, which is what makes copying /usr/bin/xdg-* out of it a faithful
# relocation rather than half an install: there is no library, no data
# directory, and nothing outside /usr/bin and /usr/share/man that xdg-open
# reads at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends xdg-utils \
 && rm -rf /var/lib/apt/lists/* \
 && command -v xdg-open \
 && mkdir -p /out/usr/bin \
 && cp -a /usr/bin/xdg-* /out/usr/bin/

# OpenAI's standalone installer, as the workload runs it, with CODEX_INSTALL_DIR
# pointed into the overlay tree instead of at /home/agent/.local/bin.
#
# The path moves on purpose: /usr/local/bin is where an overlay belongs — a
# mixin that wrote into /home/agent would land inside whatever the base (or a
# volume) has already put there — and it is on the PATH of any base carrying
# the platform floor. The workload keeps its own path because it owns its home
# directory.
#
# CODEX_NON_INTERACTIVE=true is required, not cosmetic: left unset the
# installer asks which shell profile to append PATH to, and a build has no TTY
# to answer that prompt — the RUN would hang.
#
# The install floats: no version pin, which is why the descriptor's
# `provides: ["codex"]` is unversioned and leans on its `version:` fallback.
#
# `--version` last, deliberately: the installer's exit code says only that the
# script ran, not that a usable binary landed.
ENV CODEX_INSTALL_DIR=/out/usr/local/bin
RUN mkdir -p /out/usr/local/bin \
 && CODEX_NON_INTERACTIVE=true sh -c "$(curl -fsSL https://chatgpt.com/codex/install.sh)" \
 && /out/usr/local/bin/codex --version \
 && mkdir -p /out/usr/local/share/npm-global/bin \
 && ln -sf /usr/local/bin/codex /out/usr/local/share/npm-global/bin/codex

# v2's environment.variables. A mixin's image config does not become the
# composed image's, so the exports ride the overlay and the base's login shell
# sources them.
#
# BROWSER names the xdg-open copied in above — there is still no browser and no
# display, so a link does not literally open, but xdg-open says so and exits
# non-zero, which is a diagnosable answer and Codex prints the URL.
# GIT_TERMINAL_PROMPT=0 keeps git from opening /dev/tty for a credential prompt
# nobody can answer, which would freeze Codex's TUI.
#
# IS_SANDBOX is deliberately absent: the v2 codex kit never declared it, unlike
# the sibling claude and cursor kits.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/codex-env.sh <<'EOF'
export BROWSER=xdg-open
export CODEX_HOME=/home/agent/.codex
export GIT_TERMINAL_PROMPT=0
EOF

# The overlay: the CLI, xdg-open, the npm-global shim codex-app-server's
# wrapper execs, and the profile.d exports — landing on any base.
FROM scratch
COPY --from=build /out /
