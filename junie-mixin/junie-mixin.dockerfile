# syntax=docker/dockerfile:1.7
# Overlay recipe for the junie mixin.
#
# JetBrains' install.sh is an opaque `curl | bash` with a user-scoped prefix:
# it lays the shim and its staged builds under $HOME/.local and resolves
# update state from paths it bakes there. There is no --prefix to redirect it
# at, so this takes the shape the guide prescribes for an unrelocatable
# install — the workload's own base as a build stage, the unmodified install
# run on it, and the specific resulting paths copied into a scratch overlay.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so the paths the installer bakes are already correct when the overlay lands.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

USER agent
WORKDIR /home/agent

# update-info.jsonl is what install.sh itself resolves the newest build from;
# BuildKit re-fetches it on every build to compute its digest, so this layer
# -- and the RUN below -- re-runs exactly when the stable channel has moved.
ADD --chmod=644 https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl /tmp/junie-update-info.jsonl

# `set -o pipefail`: without it, a curl failure feeding empty stdin to `bash`
# still exits 0, masking a network failure as success. JUNIE_VERSION is left
# unset so this always installs the current stable build.
RUN set -o pipefail; curl -fsSL https://junie.jetbrains.com/install.sh | bash

# The build-time gate: a broken release fails the build rather than shipping
# an overlay with a non-starting agent in it.
RUN "$HOME/.local/bin/junie" --version

USER root
# v2's image ENV, which a mixin cannot carry: a mixin's image config is not
# the composed image's, so the exports ride the overlay instead, sourced by
# the base workload's login shell.
#
# JUNIE_SKIP_UPDATE_CHECK is load-bearing rather than cosmetic: it seals the
# shim's auto-update poll, and it is why the descriptor's allow list carries
# no github.com or raw.githubusercontent.com. Run `junie` from a login shell
# so this is actually in the environment — see this kit's context file.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/junie-env.sh <<'EOF'
export JUNIE_SKIP_UPDATE_CHECK=1
EOF

# The specific resulting paths: the shim and its staged tree under ~/.local.
RUN set -eux; \
    mkdir -p /out/home/agent /out/usr/local/bin; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    chown -R 1000:1000 /out/home/agent; \
    test -x /out/home/agent/.local/bin/junie; \
    ln -s /home/agent/.local/bin/junie /out/usr/local/bin/junie

# The bin shim above, not a profile.d PATH export: v2's recipe put
# ~/.local/bin on PATH with an ENV a mixin cannot carry, and /usr/local/bin is
# on every base's PATH already.

# The overlay: the Junie install and its bin shim, landing on any base. No
# ENTRYPOINT — the base workload's launch command stays, and the user runs
# `junie` from the shell.
FROM scratch
COPY --from=build /out /
