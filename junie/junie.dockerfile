# syntax=docker/dockerfile:1.7
# Content recipe for the `junie` kit — the v2 Dockerfile, renamed to the stem
# junie.dockerfile so the descriptor beside it finds it without a
# `dockerfile:` field. Junie's own docs and README describe no Docker-backed
# tool of its own, so this uses the plain base.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# install.sh installs into $HOME/.local; run it as agent so the tree isn't root-owned.

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
# on JUNIE_VERSION, so it re-runs exactly when the pin moves and not when
# JetBrains publishes something this kit did not ask for. install.sh still
# reads the feed itself, to look up the checksum for the pinned build.

# `set -o pipefail`: without it, a curl failure feeding empty stdin to `bash`
# still exits 0, masking a network failure as success.
#
# JUNIE_VERSION is the installer's own documented pin, from its header:
# `curl -fsSL https://junie.jetbrains.com/install.sh | JUNIE_VERSION=656.1 bash`.
# Set, the script takes `VERSION="$JUNIE_VERSION"` and downloads that exact
# release instead of resolving the newest one from the feed -- and still looks
# the published checksum up for it.
RUN <<EOF
set -o pipefail -eux
test -n "${JUNIE_VERSION}" || { echo "JUNIE_VERSION is empty; pass the kit's build arg" >&2; exit 1; }
curl -fsSL https://junie.jetbrains.com/install.sh | JUNIE_VERSION="${JUNIE_VERSION}" bash
EOF

# Runs the installed binary as the build-time gate: a broken release fails the
# build. Full path because ~/.local/bin isn't on PATH yet in this RUN.
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

# Seals the shim's own auto-update check (it would otherwise poll
# update-info.jsonl and stage a new build). `--eap`/`--nightly`/
# `--experimental` one-shot channel switches still reach the network
# regardless and are outside this kit's supported surface.
#
# Load-bearing rather than cosmetic: it is why the descriptor's allow list
# carries no github.com or raw.githubusercontent.com.
ENV JUNIE_SKIP_UPDATE_CHECK=1

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "junie".
LABEL com.docker.sandboxes.flavor="junie"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

ENV PATH="/home/agent/.local/bin:${PATH}"

# v2's `sandbox.entrypoint: [junie]`, in the slot OCI already owns for launch
# config — the v3 descriptor carries none. This replaces the v2 file's
# `CMD ["junie"]` rather than joining it: the launch argv is Entrypoint + Cmd,
# so keeping both would run `junie junie`.
ENTRYPOINT ["junie"]
