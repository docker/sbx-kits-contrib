# syntax=docker/dockerfile:1.7
# Base image for the `junie` sandbox kit. Junie's own docs describe no
# Docker use of its own; the -docker base is kept because the user's
# project underneath it may need one.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# install.sh installs into $HOME/.local; run it as agent so the tree isn't root-owned.

USER agent
WORKDIR /home/agent

# update-info.jsonl is what install.sh itself resolves the newest build
# from; BuildKit re-fetches it on every build to compute its digest, so
# this layer -- and the RUN below -- re-runs exactly when the stable
# channel has moved.
ADD --chmod=644 https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl /tmp/junie-update-info.jsonl

# `set -o pipefail`: without it, a curl failure feeding empty stdin to
# `bash` still exits 0, masking a network failure as success. JUNIE_VERSION
# is left unset so this always installs the current stable build.
RUN set -o pipefail; curl -fsSL https://junie.jetbrains.com/install.sh | bash

# Runs the installed binary as the build-time gate: a broken release fails
# the build. Full path because ~/.local/bin isn't on PATH yet in this RUN.
RUN "$HOME/.local/bin/junie" --version

# Seals the shim's own auto-update check (it would otherwise poll
# update-info.jsonl and stage a new build). `--eap`/`--nightly`/
# `--experimental` one-shot channel switches still reach the network
# regardless and are outside this kit's supported surface.
ENV JUNIE_SKIP_UPDATE_CHECK=1

# Overrides the base's inherited flavor -- left alone it would report
# "shell-docker" rather than "junie".
LABEL com.docker.sandboxes.flavor="junie"

# Re-declared so the value is owned here rather than inherited from a base
# image this repository does not control.
LABEL com.docker.sandboxes.start-docker="true"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

ENV PATH="/home/agent/.local/bin:${PATH}"
CMD ["junie"]
