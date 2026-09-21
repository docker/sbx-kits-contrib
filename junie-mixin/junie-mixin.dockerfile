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

# Supplied by the descriptor's two args, which own the defaults and the
# accepted shapes. No defaults here on purpose: an unset value must fail the
# build rather than fall back to the floating channel, because the descriptor
# expands JUNIE_MARKETING_VERSION into a versioned provide.
#
#   JUNIE_VERSION           -- the JetBrains build number (3294.5). The name is
#                              install.sh's, not this kit's: the script reads
#                              exactly this variable.
#   JUNIE_MARKETING_VERSION -- the release the binary reports (26.9.21). The
#                              installer knows nothing about it; it is here
#                              only so the assertion below can check it.
ARG JUNIE_VERSION
ARG JUNIE_MARKETING_VERSION

# MIGRATION NOTE: an `ADD` of update-info.jsonl used to sit here, fetched on
# every build so its digest would invalidate this layer whenever the stable
# channel moved. A pinned install wants the opposite: the RUN below is keyed
# on JUNIE_VERSION, so it re-runs exactly when the pin moves. install.sh still
# reads the feed itself, to look up the checksum for the pinned build.

# `set -o pipefail`: without it, a curl failure feeding empty stdin to `bash`
# still exits 0, masking a network failure as success.
#
# JUNIE_VERSION is the installer's own documented pin, from its header:
# `curl -fsSL https://junie.jetbrains.com/install.sh | JUNIE_VERSION=656.1 bash`.
# Set, the script takes `VERSION="$JUNIE_VERSION"` and downloads that exact
# release instead of resolving the newest one from the feed. Keep it in step
# with ../junie.
RUN <<EOF
set -o pipefail -eux
test -n "${JUNIE_VERSION}" || { echo "JUNIE_VERSION is empty; pass the kit's build arg" >&2; exit 1; }
curl -fsSL https://junie.jetbrains.com/install.sh | JUNIE_VERSION="${JUNIE_VERSION}" bash
EOF

# The build-time gate: a broken release fails the build rather than shipping
# an overlay with a non-starting agent in it.
#
# It also gates the two pins against each other. The binary answers with both
# values on one line -- `Junie version: 26.9.21 (3294.5)` -- and the descriptor
# publishes `junie@${JUNIE_MARKETING_VERSION}` as a provide, so checking for
# both is what stops a build number quietly carrying a different marketing
# release than the one this kit claims. -F because a version is dots, not a
# regexp; -w so a declared 26.9.2 cannot be satisfied by an installed 26.9.21.
RUN <<EOF
set -eux
test -n "${JUNIE_MARKETING_VERSION}" || { echo "JUNIE_MARKETING_VERSION is empty; pass the kit's version arg" >&2; exit 1; }
"$HOME/.local/bin/junie" --version
"$HOME/.local/bin/junie" --version | grep -Fw "${JUNIE_MARKETING_VERSION}"
"$HOME/.local/bin/junie" --version | grep -Fw "${JUNIE_VERSION}"
EOF

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
