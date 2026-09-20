# syntax=docker/dockerfile:1.7
# OpenClaw as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: this kit installs a Node runtime through `n` (which writes into
# /usr/local and has no prefix indirection), then openclaw through a global
# npm install, then Chromium through playwright's installer. None of the three
# takes a relocation flag, so this takes the shape the guide prescribes for
# exactly that case -- run the unmodified install on the workload's own base,
# then copy the specific resulting paths into a scratch overlay. Everything
# lands at the absolute path it was built at, which is what keeps npm's
# relative bin symlinks resolving.
#
# WHAT THIS OVERLAY CANNOT CARRY: playwright's `install --with-deps` apt-installs
# Chromium's shared libraries, and apt packages are not copyable content -- an
# overlay can carry the browser tree but not the libraries it links against.
# The browser tool therefore works on a base that already has them (the
# sandbox-templates bases do) and fails on one that does not. There is no
# grammar to state that floor: provides/requires name kit capabilities, and no
# base workload provides an entry for its shared libraries. The workload kit
# (../openclaw) is the self-contained alternative.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

ARG OPENCLAW_VERSION
ARG TARGETARCH

USER root
# Some networks block plain-HTTP apt traffic (UA-based filtering); the
# Ubuntu archives all support HTTPS.
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

# Node 22 (openclaw requires >= 22.19) and the pinned openclaw package.
# The package's postinstall is offline-safe (local plugin fixups only).
RUN npm install -g n && n 22 && npm install -g "openclaw@${OPENCLAW_VERSION}"

# Chromium + headless deps for openclaw's browser tool. Playwright 1.60 has no
# dependency map for the template's Ubuntu 26.04 yet — override the host
# platform to 24.04 (same t64 package naming era) so the install proceeds.
RUN apt-get update && apt-get install -y --no-install-recommends xvfb && \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    PW_ARCH=$([ "$ARCH" = "amd64" ] && echo x64 || echo arm64) && \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE="ubuntu24.04-$PW_ARCH" \
      node "$(npm root -g)/openclaw/node_modules/playwright-core/cli.js" install --with-deps chromium && \
    chmod -R a+rX /opt/ms-playwright && \
    rm -rf /var/lib/apt/lists/*

# The kit's own scripts and the gateway config. This tree is a copy of
# ../openclaw/files/ and is kept byte-identical to it: a kit's build context is
# its own directory, so an overlay cannot reach the sibling workload's files/,
# and `diff -r` between the two is what catches drift. Copied without an exec
# bit, as the workload copies them, because both are invoked through `sh`.
COPY --chown=agent:agent files/home/ /out/home/agent/

# The specific paths the three installs produced.
#
# The npm prefix is asked for rather than hardcoded: `n` installs node under
# N_PREFIX (/usr/local by default) and npm's global prefix follows it, so a
# future `n` or template change that moves either would otherwise produce an
# overlay that silently contains nothing. Paths are preserved absolutely,
# which is what keeps npm's relative bin symlink into the package resolving.
# (The workload additionally re-points that symlink with `ln -sf` to guarantee
# a PATH entry; that step has nothing to add here, where the path npm wrote is
# already the one being copied.)
#
# npm rides along with node deliberately: openclaw installs plugins and
# externalized channels from the registry at run time (`/plugins install`),
# which is why registry.npmjs.org is in the descriptor's allow list, and an
# overlay that carried the agent without the package manager it shells out to
# would allow the egress and then have nothing to make the request.
RUN <<'EOF'
set -eux

prefix="$(npm prefix -g)"
root="$(npm root -g)"

# Fail loudly rather than shipping an overlay with nothing in it.
test -d "$root/openclaw"

mkdir -p "/out${prefix}/bin" "/out${root}" /out/usr/local/bin /out/opt /out/etc/profile.d

cp -a "$root/openclaw" "/out${root}/openclaw"
cp -a "$root/npm" "/out${root}/npm"
cp -a "$prefix/bin/openclaw" "/out${prefix}/bin/openclaw"
for b in node npm npx; do
  if [ -e "$prefix/bin/$b" ]; then cp -a "$prefix/bin/$b" "/out${prefix}/bin/$b"; fi
done

cp -a /opt/ms-playwright /out/opt/ms-playwright

# The launcher the workload also ships at this path, for `openclaw-start` from
# the shell.
install -m 0755 /out/home/agent/.local/bin/openclaw-start.sh /out/usr/local/bin/openclaw-start

chown -R 1000:1000 /out/home/agent
EOF

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead.
COPY <<'EOF' /out/etc/profile.d/openclaw-env.sh
export OPENCLAW_STATE_DIR=/home/agent/.openclaw
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
EOF

# The overlay: node, the agent, the browser and the kit's scripts, landing on
# any base.
FROM scratch
COPY --from=build /out /
