# syntax=docker/dockerfile:1.7
# Paperclip as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: this kit installs a Node runtime through `n` (which writes into
# /usr/local and has no prefix indirection) and then paperclipai through a
# global npm install. Neither takes a relocation flag, so this takes the shape
# the guide prescribes for exactly that case -- run the unmodified install on
# the workload's own base, then copy the specific resulting paths into a
# scratch overlay. Everything lands at the absolute path it was built at,
# which is what keeps npm's relative bin symlinks resolving.
#
# WHAT THIS OVERLAY CANNOT CARRY:
#
#   * Distro PostgreSQL. The workload apt-installs it because paperclip's
#     bundled embedded-postgres binaries are linked for 4KB pages and fail to
#     load on the sandbox microVM's 16KB-page arm64 kernel. apt packages are
#     not copyable content: the tree under /usr/lib/postgresql links against
#     libicu, libssl and friends that the overlay would have to guess at, and
#     the dpkg state does not travel. start-paperclip.sh fails loudly under
#     `set -e` on a base without it.
#   * Claude Code. The workload gets it from the claude-code template base,
#     which is what paperclip's `claude_local` adapter shells out to.
#
# See paperclip-mixin.yaml and this kit's README for why neither is stated as
# a `requires`. The workload kit (../paperclip) is the self-contained
# alternative.
ARG BASE_IMAGE=docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg, handed here as a build arg.
ARG PAPERCLIP_VERSION=2026.609.0

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering); the
# Ubuntu archives all support HTTPS.
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Node 22 (paperclip requires >=20; its own agent images use 22) and the
# pinned paperclipai CLI. The install pulls @paperclipai/server, the built UI,
# embedded-postgres platform binaries, and sharp prebuilds.
RUN npm install -g n && n 22 && npm install -g "paperclipai@${PAPERCLIP_VERSION}"

# The kit's own scripts.
#
# MIGRATION NOTE: files/ and scripts/ here are copies of ../paperclip/files/
# and ../paperclip/scripts/, not references to them. A kit's build context is
# rooted at its own descriptor's directory and may not escape it
# (SPEC-v3 §4), so a sibling kit's assets are unreachable from here. They must
# move together -- see this kit's README. files/home/ is copied without an
# exec bit, as the workload copies it, because paperclip-anthropic-auth.sh is
# invoked through `sh`.
COPY --chown=agent:agent files/home/ /out/home/agent/

# The specific paths the two installs produced.
#
# npm and npx ride along with node deliberately: the server spawns agent CLIs
# as child processes and resolves them through the Node toolchain, and an
# overlay that carried the app without the runtime it executes on would be
# inert on a base with no Node.
#
# /usr/local/bin/paperclipai is npm's own relative symlink into the package,
# copied as a symlink: both ends land at the same absolute paths here, so it
# resolves in the overlay. (The workload additionally re-points it with
# `ln -sf` to guarantee a PATH entry; that step has nothing to add here,
# where the same path is already what npm wrote.)
RUN set -eu; \
    mkdir -p /out/usr/local/bin /out/usr/local/lib/node_modules /out/etc/profile.d; \
    cp -a /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /out/usr/local/bin/; \
    cp -a /usr/local/lib/node_modules/npm /out/usr/local/lib/node_modules/npm; \
    cp -a /usr/local/lib/node_modules/paperclipai /out/usr/local/lib/node_modules/paperclipai; \
    cp -a /usr/local/bin/paperclipai /out/usr/local/bin/paperclipai

# The server start script (the workload's image-baked /usr/local/bin/
# paperclip-start) and the kit's wrapper around it, which sources the auth
# env file the startup hook writes. A mixin sets no entrypoint, so the
# wrapper lands as a 0755 launcher on PATH: it is how a user gets the
# workload's launch behaviour in one word.
COPY --chmod=0755 scripts/start-paperclip.sh /out/usr/local/bin/paperclip-start
RUN install -m 0755 /out/home/agent/.local/bin/paperclip-start.sh /out/usr/local/bin/paperclip \
 && mkdir -p /out/home/agent/.paperclip \
 && chown -R 1000:1000 /out/home/agent

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead.
#
# PAPERCLIP_HOME matters twice over here: it is the state root, and it is
# what the descriptor's startup hook names in its `env:` list so the hook and
# the launcher agree on where the auth env file goes.
COPY <<'EOF' /out/etc/profile.d/paperclip-env.sh
export HOST=0.0.0.0
export PAPERCLIP_BIND=lan
export PAPERCLIP_DEPLOYMENT_MODE=authenticated
export PAPERCLIP_HOME=/home/agent/.paperclip
export PAPERCLIP_TELEMETRY_DISABLED=1
export SERVE_UI=true
EOF

# The overlay: Node, the app, and the kit's scripts, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
