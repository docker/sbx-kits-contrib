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
RUN mkdir -p /out/opt /out/usr/local/bin \
 && cp -a /opt/opencode /out/opt/opencode \
 && cp -a "$(command -v node)" /out/usr/local/bin/node

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
