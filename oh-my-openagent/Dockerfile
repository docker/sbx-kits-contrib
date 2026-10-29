# syntax=docker/dockerfile:1

# Base image for the `oh-my-openagent` sandbox kit.
#
# Pre-bakes `omo-ai` so sandbox creation is fast: the `omo` binary is already
# on the image and `sbx create` pays no npm install.
#
# Built and published by build-and-publish-kits.yml (see ../PUBLISHING.md) --
# no bespoke workflow needed, same as pi/aider/codex/opencode/senpi.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker.io/sbx/shell-image:latest
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# omo's engines require Node >= 24; the shell base ships an older
# Node, so install Node 24 from NodeSource before installing the agent.
USER root
RUN <<'EOF'
set -euxo pipefail
apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && \
    npm --version
EOF

USER agent
WORKDIR /home/agent

# omo-ai is the OmO native package; it ships the `omo` binary and pulls
# @code-yeongyu/senpi internally, so no separate platform package is needed.
ARG TARGETARCH
ARG OMO_VERSION=5.1.48
RUN npm install -g "omo-ai@${OMO_VERSION}" \
    && omo --version

USER root
RUN ln -sf "$(npm prefix -g)/bin/omo" /usr/local/bin/omo

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance.
LABEL com.docker.sandboxes.flavor="omo"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD [ "omo" ]
