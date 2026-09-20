# syntax=docker/dockerfile:1

# Overlay recipe for the copilot mixin: the same vendor install the copilot
# workload kit does, landed under /out and shipped as a `FROM scratch` delta
# that composes onto any base rather than as a root filesystem of its own.
#
# The build stage is the workload's own base, verbatim.
#
# GitHub's installer takes no target-directory option and lays the CLI under
# $HOME/.local, so the relocation runs it against a scratch HOME and moves the
# tree afterwards rather than trying to talk the installer into writing
# somewhere else. The tree lands at a stable /opt path with a /usr/local/bin
# shim: an overlay that wrote into /home/agent would land inside whatever the
# base (or a mounted volume) has already put there.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# `test -x` after the install, carried over from the workload recipe's reasoning
# about the cursor installer and applied here for the same reason: a completed
# install command proves an exit code, not an installed binary, and an overlay
# with no agent in it would otherwise build "successfully".
#
# The whole installed tree moves rather than a hand-picked list of files: the
# vendor owns that layout, and a release that grows a sibling asset would
# otherwise be silently truncated by the overlay.
#
# The install floats: no version pin, which is why the descriptor's
# `provides: ["copilot"]` is unversioned and leans on its `version:` fallback.
RUN <<EOF
set -exo pipefail
mkdir -p /build /out/opt /out/usr/local/bin
HOME=/build bash -c 'curl -fsSL https://gh.io/copilot-install | bash'
test -x /build/.local/bin/copilot
cp -a /build/.local /out/opt/copilot-cli
# The installer may leave bin/copilot as a symlink into a versions tree under
# the scratch HOME. Rewrite that prefix to the overlay's /opt path so the shim
# resolves once the tree has moved; a plain file needs no rewrite.
if [ -L /build/.local/bin/copilot ]; then
    target=$(readlink -f /build/.local/bin/copilot | sed 's#^/build/\.local#/opt/copilot-cli#')
else
    target=/opt/copilot-cli/bin/copilot
fi
ln -s "$target" /out/usr/local/bin/copilot
EOF

# No /etc/profile.d drop: the v2 copilot kit declared no environment.variables,
# so unlike the codex and cursor mixins there is nothing for one to carry.

# The overlay: the CLI tree and its bin shim, landing on any base.
FROM scratch
COPY --from=build /out /
