# syntax=docker/dockerfile:1

# Overlay recipe for the copilot mixin: the same vendor install the copilot
# workload kit does, landed under /out and shipped as a `FROM scratch` delta
# that composes onto any base rather than as a root filesystem of its own.
#
# The build stage is the workload's own base, verbatim.
#
# GitHub's installer does take a target-directory option — PREFIX, documented in
# the script's own header, installing to $PREFIX/bin. What it does not honor is
# HOME: it picks the prefix from the effective uid, defaulting to /usr/local for
# root and only falling back to $HOME/.local for the non-root case. This stage
# runs as root, so redirecting the install with HOME=/build is a no-op — the CLI
# lands in the stage's own /usr/local/bin and the overlay ships nothing.
#
# So PREFIX points straight at the staging tree and the CLI arrives in its final
# layout in one step, with no post-hoc move. The tree lands at a stable /opt path
# with a /usr/local/bin shim: an overlay that wrote into /home/agent would land
# inside whatever the base (or a mounted volume) has already put there.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# `test -x` after the install, carried over from the workload recipe's reasoning
# about the cursor installer and applied here for the same reason: a completed
# install command proves an exit code, not an installed binary, and an overlay
# with no agent in it would otherwise build "successfully".
#
# The whole prefix is staged rather than a hand-picked list of files: the vendor
# owns that layout, and a release that grows a sibling asset beside the binary
# would otherwise be silently truncated by the overlay.
#
# The install floats: no version pin, which is why the descriptor's
# `provides: ["copilot"]` is unversioned and leans on its `version:` fallback.
RUN <<EOF
set -exo pipefail
mkdir -p /out/opt /out/usr/local/bin
export PREFIX=/out/opt/copilot-cli
# The staging bin dir goes on PATH so the installer's own `command -v copilot`
# check passes. Without it the installer takes its "not in your PATH" branch,
# which opens /dev/tty to offer appending a PATH line to root's .profile — log
# noise here, and a write to a file the overlay has no business carrying.
export PATH="$PREFIX/bin:$PATH"
curl -fsSL https://gh.io/copilot-install | bash
# Asserted against the literal path rather than $PREFIX: the guard is here to
# catch the overlay's contract breaking, and one phrased in the same variable
# that chose the location would agree with itself wherever that location moved.
test -x /out/opt/copilot-cli/bin/copilot
# The release tarball records uid 1001, which a root `tar -xz` preserves. On an
# unknown base that uid belongs to somebody, so the binary sitting on the shared
# PATH is normalized to root; the directories around it are already root-owned.
chown -R 0:0 /out/opt/copilot-cli
# A plain file, not a symlink into a versions tree — the installer's entire
# install step is `tar -xz -C $PREFIX/bin` plus a chmod. And since PREFIX staged
# the tree where it will finally sit, there is no relocation for the shim to
# chase: it is a fixed link to the path the overlay lands the tree on.
ln -s /opt/copilot-cli/bin/copilot /out/usr/local/bin/copilot
EOF

# No /etc/profile.d drop: the v2 copilot kit declared no environment.variables,
# so unlike the codex and cursor mixins there is nothing for one to carry.

# The overlay: the CLI tree and its bin shim, landing on any base.
FROM scratch
COPY --from=build /out /
