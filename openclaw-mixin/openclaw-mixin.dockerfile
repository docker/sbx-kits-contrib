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
#
# Deliberately without the `--chown=agent:agent` the workload's copy of this
# same tree carries: BuildKit applies --chown to every parent directory it
# creates, so chowning into /out/home/agent/ also stamps uid 1000 onto
# /out/home, and the `chown -R /out/home/agent` at the end of the next stanza
# starts one level too deep to undo it. The overlay would then ship `home/`
# owned by the agent -- an overlay's directory entries override the base's, so
# that hands away a directory this kit does not own. Root-owned parents here;
# agent ownership is applied below, starting exactly at the agent's home.
COPY files/home/ /out/home/agent/

# The specific paths the three installs produced.
#
# There are two prefixes here, not one. The template base exports
# NPM_CONFIG_PREFIX=/usr/local/share/npm-global, so a `npm install -g` lands
# the package there, while `n` installs the node runtime -- and the npm that
# comes inside the node tarball -- under N_PREFIX (/usr/local). npm is
# therefore not a global package on this base and does not appear under
# `npm root -g` at all; it sits beside node, in node's own prefix. Both
# prefixes are asked for rather than hardcoded, and both are asserted, so a
# future `n` or template change that moves either fails this build instead of
# producing an overlay that silently contains nothing.
#
# Paths are preserved absolutely, which is what keeps npm's relative bin
# symlink into the package ($prefix/bin/openclaw -> ../lib/node_modules/
# openclaw/...) resolving once it lands.
#
# npm rides along with node deliberately: openclaw installs plugins and
# externalized channels from the registry at run time (`/plugins install`),
# which is why registry.npmjs.org is in the descriptor's allow list, and an
# overlay that carried the agent without the package manager it shells out to
# would allow the egress and then have nothing to make the request.
RUN <<'EOF'
set -eux

# Where global packages go (openclaw) ...
prefix="$(npm prefix -g)"
root="$(npm root -g)"
# ... and where the runtime itself went (node, npm, npx). Derived from the
# binary rather than assumed to equal $prefix, which is the assumption that
# made this stanza look for npm under the global root.
node_prefix="$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")"

# Fail loudly rather than shipping an overlay with nothing in it. Four
# assertions because there are four independently movable things below, and a
# missing one is invisible at build time and fatal at run time.
test -d "$root/openclaw"
test -e "$prefix/bin/openclaw"
test -x "$node_prefix/bin/node"
test -d "$node_prefix/lib/node_modules/npm"

mkdir -p "/out${prefix}/bin" "/out${root}" \
         "/out${node_prefix}/bin" "/out${node_prefix}/lib/node_modules" \
         /out/usr/local/bin /out/opt /out/etc/profile.d

cp -a "$root/openclaw" "/out${root}/openclaw"
cp -a "$prefix/bin/openclaw" "/out${prefix}/bin/openclaw"

cp -a "$node_prefix/bin/node" "/out${node_prefix}/bin/node"
cp -a "$node_prefix/lib/node_modules/npm" "/out${node_prefix}/lib/node_modules/npm"
# npm and npx are relative symlinks into the tree copied a line above, so they
# travel as symlinks and resolve. corepack is deliberately not copied: its
# link would dangle without its own module tree, which nothing here needs.
for b in npm npx; do
  cp -a "$node_prefix/bin/$b" "/out${node_prefix}/bin/$b"
done

# npm tarballs preserve whatever uid the publisher's machine had, and `cp -a`
# carries it into the overlay: this tree arrives with files owned by 501:20 (a
# macOS developer), 1001:127 (a CI runner) and worse. In a create-time hook
# those ids were harmless because the install ran against the real base; as
# image content on an unknown base they may be real accounts, and a file's
# owner can rewrite it whatever its mode says. Normalized to root, which is
# how a root-installed global package looks anyway -- the agent needs write
# access to the prefix directories to add packages, not to openclaw's own tree.
chown -R 0:0 "/out${root}/openclaw" "/out${node_prefix}/lib/node_modules/npm"

# The base owns the global prefix root as agent:agent, so the agent can
# `npm install -g` without sudo -- which is exactly what openclaw's runtime
# plugin installs do. mkdir above created it root-owned, and an overlay's
# directory entries override the base's, so without this the overlay would
# quietly take that away.
chown 1000:1000 "/out${prefix}"

# /usr/local/bin/openclaw, the same symlink the workload pins. Not redundant
# here, despite the copy of npm's own bin entry above: $prefix/bin is only on
# PATH because *this* base puts it there, an overlay lands on a base that may
# not, and openclaw-gateway-up.sh resets PATH to /usr/local/bin:/usr/bin:/bin
# for exactly that reason -- so without this, the kit's own startup hook
# cannot find the agent the overlay just delivered. Absolute, because a copy
# of npm's relative link would resolve against /usr/local/lib from here.
ln -sf "$prefix/bin/openclaw" /out/usr/local/bin/openclaw

cp -a /opt/ms-playwright /out/opt/ms-playwright

# The launcher the workload also ships at this path, for `openclaw-start` from
# the shell.
install -m 0755 /out/home/agent/.local/bin/openclaw-start.sh /out/usr/local/bin/openclaw-start

# Starts exactly at the agent's home: /out/home stays root-owned, as the base
# has it.
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
