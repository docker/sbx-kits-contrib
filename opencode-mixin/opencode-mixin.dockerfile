# syntax=docker/dockerfile:1
# OpenCode as an overlay.
#
# Unlike this repo's other agent mixins, the install here DOES relocate: `npm
# install -g --prefix` puts the package anywhere, so the overlay does not have
# to reproduce a tree at the path it was built at. What it still cannot do is
# change base -- the workload's own base is used as the build stage because
# that is where the corepack hazard below is real and where the `--version`
# gate means something. Keeping the base verbatim is also what makes the
# platform binary npm's postinstall selects match the bases this composes onto.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Pin a release by passing --build-arg OPENCODE_VERSION=1.2.3 (npm semver, no
# leading "v"). Left empty, the build installs the newest published version --
# which is why the descriptor's provide is unversioned.
ARG OPENCODE_VERSION=""

# /opt belongs to root and this base runs as the unprivileged `agent` (uid
# 1000), so npm cannot create the prefix it is pointed at. The prefix is
# created as root and handed over rather than the install being run as root,
# because root is exactly the wrong user for the corepack line below: corepack
# `disable` unlinks npm's bin path WITHOUT checking that a corepack shim is
# what sits there -- its removePosixLink is an unconditional unlink. As root
# that deletes this base's distro /usr/bin/npm symlink outright, and the
# install on the next line then has no npm to run; as the agent it is the
# harmless EACCES the `||` branch exists for. Running as the base's own user
# is also what keeps this install identical to the workload's, which is the
# whole reason this stage builds on the workload's base.
USER root
RUN mkdir -p /opt/opencode && chown agent:agent /opt/opencode
USER agent

# Installed from npm rather than through the standalone
# `curl https://opencode.ai/install | bash` script upstream's README leads
# with: the npm route resolves nothing through the unauthenticated GitHub
# releases API, so a busy shared runner's rate limit cannot fail the build.
#
# Two things the install line has to get right, and both carry over from the
# workload unchanged:
#
#   - The published package's bin/opencode.exe is a stub; its postinstall
#     script replaces it with the platform binary it selects from the package's
#     optional dependencies, matching architecture, libc and (on x86) AVX2
#     support. A corepack-managed npm shim does not run lifecycle scripts, so
#     installing through one would ship the stub and still exit 0. Disabling
#     the shim first is therefore a correctness step, not tidying — and it is
#     allowed to fail: on a base whose npm is a distro binary rather than a
#     corepack shim there is nothing to disable and nothing to remove.
#   - `--include=optional` restates npm's own default so an inherited
#     `omit=optional` — from an .npmrc or from NPM_CONFIG_OMIT — cannot leave
#     the postinstall with no binary to copy.
#
# The `--version` call last, deliberately: the install's exit code says only
# that npm ran, not that a working binary came out of it. It runs against the
# real /opt/opencode prefix — the path the overlay will land at — so what is
# verified is what ships. The npm cache is dropped in the same layer because it
# holds a second copy of a ~180 MB tarball that nothing reads again.
RUN <<EOF
set -eux

(corepack disable npm 2>&1 || echo "no corepack npm shim to disable")

npm install -g --prefix /opt/opencode "opencode-ai@${OPENCODE_VERSION:-latest}" --include=optional

/opt/opencode/bin/opencode --version

npm cache clean --force
rm -rf "${HOME}/.npm"
EOF

# The launcher goes through npm's own bin entry rather than reaching into the
# package for a file path. That entry is whatever the postinstall left there —
# a native platform binary on a supported arch, a node script otherwise — and a
# shim that assumed one shape would break on the other. Prepending
# /usr/local/bin is what makes the node case work, since the overlay's own node
# lands there.
#
# Root for the staging step only -- everything above deliberately runs as the
# base's `agent` user, and /out cannot be created under a root-owned /. The
# staged tree is chowned back because an overlay's directory entries override
# the base's: /opt and /usr/local/bin are root's on every base this composes
# onto, and root's mkdir here gives them that, but `cp -a` would otherwise
# carry the install's uid onto /opt/opencode and hand a 180 MB executable the
# launcher runs to whoever uid 1000 turns out to be on that base. Nothing
# writes into the prefix at run time -- see the self-update note below.
# Numeric because scratch carries no /etc/passwd for a name to resolve against.
# No node is copied out. The package's bin entry resolves to a native ELF that
# links only libc, libpthread and libdl, so the overlay needs no runtime --
# verified by composing this overlay onto a node-free ubuntu:24.04, where
# `opencode --version` reports 1.18.31. Copying the template's node would also
# be worse than useless: Debian's /usr/bin/node is a small launcher linked
# against libnode.so.127, which a bare copy cannot resolve, and /usr/local/bin
# precedes /usr/bin on PATH -- so it would shadow a working node on any base
# that has one with a broken one.
USER root
RUN mkdir -p /out/opt /out/usr/local/bin \
 && cp -a /opt/opencode /out/opt/opencode \
 && chown -R 0:0 /out/opt/opencode

COPY --chmod=755 <<'EOF' /out/usr/local/bin/opencode
#!/bin/sh
PATH="/usr/local/bin:$PATH"
export PATH
exec /opt/opencode/bin/opencode "$@"
EOF

# NOTE on self-update: `opencode upgrade` reinstalls from npm into the global
# prefix of whatever node is first on PATH, which in a composed sandbox is the
# base's prefix and not /opt/opencode. The shim above keeps pointing at the
# version this kit built, so an upgrade inside the sandbox lands a second copy
# the launcher does not use. The workload kit installs into the global prefix
# and does not have this seam; here the kit's build is the version of record.

# The overlay: node, the package and the launcher, landing on any base.
FROM scratch
COPY --from=build /out /
