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
#
# Deliberately without the `--chown=agent:agent` the workload's copy of this
# same tree carries: BuildKit applies --chown to every parent directory it
# creates, so chowning into /out/home/agent/ also stamps uid 1000 onto
# /out/home, and the `chown -R /out/home/agent` further down starts one level
# too deep to undo it. The overlay would then ship `home/` owned by the agent
# -- an overlay's directory entries override the base's, so that hands away a
# directory this kit does not own. Root-owned parents here; agent ownership is
# applied below, starting exactly at the agent's home.
COPY files/home/ /out/home/agent/

# The specific paths the two installs produced.
#
# There are two prefixes here, not one, which is why none of these paths is
# hardcoded. The template base exports
# NPM_CONFIG_PREFIX=/usr/local/share/npm-global, so `npm install -g
# paperclipai` lands the package and its bin entry *there* -- not at npm's
# compiled-in default of /usr/local/lib/node_modules, which is where `n` put
# node and the npm that came inside the node tarball. Asking npm for its own
# prefix and deriving node's from the binary keeps the two apart, and the
# assertions below turn a template change that moves either into a failed
# build rather than an overlay with no app in it.
#
# Paths are preserved absolutely, which is what keeps npm's relative bin
# symlink into the package ($prefix/bin/paperclipai -> ../lib/node_modules/
# paperclipai/...) resolving once it lands.
#
# npm and npx ride along with node deliberately: the server spawns agent CLIs
# as child processes and resolves them through the Node toolchain, and an
# overlay that carried the app without the runtime it executes on would be
# inert on a base with no Node.
RUN <<'EOF'
set -eux

# Where global packages go (paperclipai) ...
prefix="$(npm prefix -g)"
root="$(npm root -g)"
# ... and where the runtime itself went (node, npm, npx).
node_prefix="$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")"

# Fail loudly rather than shipping an overlay with nothing in it. Four
# assertions because there are four independently movable things below, and a
# missing one is invisible at build time and fatal at run time.
test -d "$root/paperclipai"
test -e "$prefix/bin/paperclipai"
test -x "$node_prefix/bin/node"
test -d "$node_prefix/lib/node_modules/npm"

mkdir -p "/out${prefix}/bin" "/out${root}" \
         "/out${node_prefix}/bin" "/out${node_prefix}/lib/node_modules" \
         /out/usr/local/bin /out/etc/profile.d

cp -a "$root/paperclipai" "/out${root}/paperclipai"
cp -a "$prefix/bin/paperclipai" "/out${prefix}/bin/paperclipai"

cp -a "$node_prefix/bin/node" "$node_prefix/bin/npm" "$node_prefix/bin/npx" "/out${node_prefix}/bin/"
cp -a "$node_prefix/lib/node_modules/npm" "/out${node_prefix}/lib/node_modules/npm"

# npm tarballs preserve whatever uid the publisher's machine had, and `cp -a`
# carries it into the overlay: this tree arrives with files owned by 501:20 (a
# macOS developer) and 1001:127 (a CI runner). In a create-time hook those ids
# were harmless because the install ran against the real base; as image content
# on an unknown base they may be real accounts, and a file's owner can rewrite
# it whatever its mode says. Normalized to root, which is how a root-installed
# global package looks anyway -- the agent needs write access to the prefix
# directories to add packages, not to paperclipai's own tree.
chown -R 0:0 "/out${root}/paperclipai" "/out${node_prefix}/lib/node_modules/npm"

# The base owns the global prefix root as agent:agent so the agent can
# `npm install -g` without sudo. mkdir above created it root-owned, and an
# overlay's directory entries override the base's, so without this the overlay
# would quietly take that away.
chown 1000:1000 "/out${prefix}"

# /usr/local/bin/paperclipai, the same symlink the workload pins. Not
# redundant here, despite the copy of npm's own bin entry above: $prefix/bin
# is only on PATH because *this* base puts it there, and an overlay lands on a
# base that may not -- while start-paperclip.sh ends in `exec paperclipai
# onboard --yes` and needs to find it. Absolute, because a copy of npm's
# relative link would resolve against /usr/local/lib from here.
ln -sf "$prefix/bin/paperclipai" /out/usr/local/bin/paperclipai
EOF

# The server start script (the workload's image-baked /usr/local/bin/
# paperclip-start) and the kit's wrapper around it, which sources the auth
# env file the startup hook writes. A mixin sets no entrypoint, so the
# wrapper lands as a 0755 launcher on PATH: it is how a user gets the
# workload's launch behaviour in one word.
COPY --chmod=0755 scripts/start-paperclip.sh /out/usr/local/bin/paperclip-start

# The chown starts exactly at the agent's home: /out/home stays root-owned, as
# the base has it.
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
