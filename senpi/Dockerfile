# syntax=docker/dockerfile:1

# Base image for the `senpi` sandbox kit.
#
# Pre-bakes `@code-yeongyu/senpi` so sandbox creation is fast: the `senpi`
# binary is already on the image and `sbx create` pays no npm install.
#
# Built and published by build-and-publish-kits.yml (see ../PUBLISHING.md) --
# no bespoke workflow needed, same as pi/aider/codex/opencode.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker.io/sbx/shell-image:latest
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# senpi's engines require Node >= 24; the shell base ships an older Node, so
# install Node 24 from NodeSource before installing the agent.
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

# Install senpi from npm into the agent-owned global prefix, then symlink it
# onto /usr/local/bin so it resolves on every PATH (startup hooks and exec
# paths can run with a minimal PATH). The global bin dir is on PATH in this
# image, but not in every context that may invoke the binary. Installing as
# `agent` keeps the global prefix agent-owned (it is chowned in the base
# image), which is what pi does too.
ARG SENPI_VERSION=latest
RUN npm install -g "@code-yeongyu/senpi@${SENPI_VERSION}" \
    && senpi --version

USER root
RUN ln -sf "$(npm prefix -g)/bin/senpi" /usr/local/bin/senpi

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance.
LABEL com.docker.sandboxes.flavor="senpi"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD [ "senpi" ]
