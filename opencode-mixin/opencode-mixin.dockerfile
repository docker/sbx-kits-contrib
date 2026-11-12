# syntax=docker/dockerfile:1
# OpenCode as an overlay.
#
# OpenCode v2 ships as a single native binary, so the overlay does not have to
# reproduce a tree at the path it was built at: the binary is copied out to
# /opt/opencode wherever the installer put it. What the build still cannot do is
# change base -- the workload's own base is used as the build stage because that
# is where the `--version` gate means something, and because the installer picks
# the libc variant from the system it runs on. Keeping the base verbatim is what
# makes that variant match the bases this composes onto.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg arriving as a build arg -- opencode-mixin.yaml
# declares it with `buildArg: OPENCODE_VERSION`, validates its shape, and
# expands the same value into `provides: ["opencode@..."]`. Deliberately no
# default here: the descriptor is the single source of the pin. Move it with
# `--build-arg version=1.2.3` (no leading "v"), which moves the install and the
# provide together.
ARG OPENCODE_VERSION

# The official v2 installer, the same one the workload uses. It downloads and
# extracts the platform binary directly from the npm registry, selecting the
# architecture, libc and x86 AVX2 variant itself, without requiring npm or Node
# at build time.
#
# It runs as the base's own `agent` user and installs into that user's
# ~/.opencode/bin, exactly as in the workload; the binary is relocated to
# /opt/opencode in the staging step below. `--no-modify-path` keeps the
# installer from editing shell startup files that nothing in the overlay ships.
#
# Download before executing so a failed transfer cannot be mistaken for a
# successful empty shell script. `--version` last, deliberately: the
# installer's exit code says only that it ran, not that a working binary came
# out of it, and it prints the bare version string, so the build log records
# what the pin resolved to.
RUN <<EOF
set -eux

curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install
if [ -n "${OPENCODE_VERSION:-}" ]; then
  bash /tmp/opencode-install --version "${OPENCODE_VERSION}" --no-modify-path
else
  bash /tmp/opencode-install --no-modify-path
fi
rm -f /tmp/opencode-install

"${HOME}/.opencode/bin/opencode" --version
EOF

# Root for the staging step only -- the install above deliberately runs as the
# base's `agent` user, and /out cannot be created under a root-owned /. The
# staged tree is chowned to root because an overlay's directory entries override
# the base's: /opt and /usr/local/bin are root's on every base this composes
# onto, and root's mkdir here gives them that, but `cp -a` would otherwise carry
# the install's uid onto /opt/opencode and hand an executable the launcher runs
# to whoever uid 1000 turns out to be on that base. Numeric because scratch
# carries no /etc/passwd for a name to resolve against.
#
# No runtime is copied out: the binary is native and self-contained, so the
# overlay lands on any base of the same architecture and libc.
USER root
RUN mkdir -p /out/opt/opencode /out/usr/local/bin \
 && cp -a /home/agent/.opencode/bin /out/opt/opencode/bin \
 && chown -R 0:0 /out/opt/opencode

COPY --chmod=755 <<'EOF' /out/usr/local/bin/opencode
#!/bin/sh
exec /opt/opencode/bin/opencode "$@"
EOF

# NOTE on self-update: the workload's binary sits in an `agent`-owned prefix,
# so OpenCode's native updater can replace it in place. Here /opt/opencode is
# root's, so the updater cannot replace the binary the launcher runs; the kit's
# build is the version of record. Move it with the `version` arg instead.

# The overlay: the binary and the launcher, landing on any base.
FROM ${BASE_IMAGE} AS verified
USER root
COPY --from=build /out /out
COPY --from=build /out /
USER agent
RUN --network=none command -v opencode \
    && { output="$(opencode --version 2>&1)"; status=$?; \
         printf '%s\n' "$output"; test "$status" -eq 0 && test -n "$output"; }

FROM scratch
COPY --from=verified /out /
