# syntax=docker/dockerfile:1

# Base image for the `shell` sandbox kit: the sandbox toolchain, the non-root
# `agent` user and a Docker engine, built here from Ubuntu rather than
# inherited. Owning the recipe is what lets this image become the base other
# kits build on; while the shared sandbox template still exists, the stages
# below are kept identical to its `shell-docker` chain so the two stay
# diffable, except for two comments reworded to drop private references.

ARG UBUNTU_VERSION="26.04"
ARG UV_VERSION="0.9.26"
# Pinned release of docker/clipboardbridge — the prebuilt clipboard-bridge
# binary copied into the base image below. Bump in lockstep with a CI build.
ARG CLIPBOARD_BRIDGE_VERSION="v0.3.0"

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

##############
# Base image #
##############
FROM ubuntu:${UBUNTU_VERSION} AS base

# Declare build platform args to ensure cache invalidation across platforms
ARG TARGETPLATFORM

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/home/agent/.local/bin:/usr/local/share/npm-global/bin:$PATH

# Configure NO_PROXY to include Docker bridge network for Testcontainers-like compatibility
# Testcontainers-like environments need to access container IPs (172.17.0.0/16) without going through proxy
ENV NO_PROXY=localhost,127.0.0.1,::1,172.17.0.0/16
ENV no_proxy=localhost,127.0.0.1,::1,172.17.0.0/16

WORKDIR /home/agent/workspace

# Install packages
RUN <<EOF
set -euxo pipefail
# Add Docker repos
apt-get update
apt-get install -yy --no-install-recommends \
    ca-certificates \
    curl \
    gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
EOF

# Configure users, sandbox config, and npm
RUN <<EOF
set -ex
# Remove base image user
userdel ubuntu || true

# Create non-root user
useradd --create-home --uid 1000 --shell /bin/bash agent
groupadd -f docker
usermod -aG sudo agent
usermod -aG docker agent

# Configure sudoers
mkdir /etc/sudoers.d
chmod 0755 /etc/sudoers.d
echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent
echo "Defaults:%sudo env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY SSL_CERT_FILE NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE JAVA_TOOL_OPTIONS\"" > /etc/sudoers.d/proxyconfig

# Create sandbox config
mkdir -p /home/agent/.docker/sandbox/locks

# Pre-create .local directories with correct ownership to prevent OCI runtime
# from creating them as root when mounting volumes at deep paths like
# /home/agent/.local/share/opencode.
mkdir -p /home/agent/.local/share /home/agent/.local/state

chown -R agent:agent /home/agent

# Set up npm global package folder under /usr/local/share
mkdir -p /usr/local/share/npm-global
chown -R agent:agent /usr/local/share/npm-global
EOF

# Create persistent environment shell script that will be sourced by all shell sessions
RUN touch /etc/sandbox-persistent.sh && \
    chmod 644 /etc/sandbox-persistent.sh && \
    chown agent:agent /etc/sandbox-persistent.sh

# Set BASH_ENV to auto-source persistent env for non-interactive shells
ENV BASH_ENV=/etc/sandbox-persistent.sh

# Configure login shells to source persistent environment
RUN <<EOF
set -ex
cat > /etc/profile.d/sandbox-persistent.sh << 'PROFILEEOF'
# Source the sandbox persistent environment file
if [ -f /etc/sandbox-persistent.sh ]; then
    . /etc/sandbox-persistent.sh
fi

# Export BASH_ENV so non-interactive child shells also source the persistent env
export BASH_ENV=/etc/sandbox-persistent.sh
PROFILEEOF
chmod 644 /etc/profile.d/sandbox-persistent.sh
EOF

# Configure bash to always source persistent environment
# IMPORTANT: Prepend to existing /etc/bash.bashrc to preserve Ubuntu defaults
RUN <<EOF
set -ex
# Create our prepend content
cat > /tmp/sandbox-bashrc-prepend << 'PREPEND'
# Docker Sandbox: Source persistent environment for interactive shells
if [ -f /etc/sandbox-persistent.sh ]; then
    . /etc/sandbox-persistent.sh
fi

# Export BASH_ENV so non-interactive child shells also source the persistent env
export BASH_ENV=/etc/sandbox-persistent.sh

PREPEND

# Prepend our content to existing bashrc
cat /tmp/sandbox-bashrc-prepend /etc/bash.bashrc > /tmp/new-bashrc
mv /tmp/new-bashrc /etc/bash.bashrc
chmod 644 /etc/bash.bashrc
rm /tmp/sandbox-bashrc-prepend
EOF

# Create user bashrc to source persistent environment for interactive shells
RUN <<EOF
set -ex
cat > /home/agent/.bashrc << 'BASHRCEOF'
# Source the sandbox persistent environment file
if [ -f /etc/sandbox-persistent.sh ]; then
    . /etc/sandbox-persistent.sh
fi

# Export BASH_ENV for child non-interactive shells
export BASH_ENV=/etc/sandbox-persistent.sh

# Enable colorized ls output by default
alias ls='ls --color=auto'
BASHRCEOF
chmod 644 /home/agent/.bashrc
chown agent:agent /home/agent/.bashrc
EOF

# Install uv from official GitHub releases
COPY --link --from=uv /uv /usr/local/bin/uv

# Clipboard bridge: a minimal Wayland wlr-data-control server that lets agents
# paste host images/screenshots (Ctrl+V) when they read the clipboard via a
# native library rather than wl-paste/xclip (e.g. Codex via arboard). Fetched
# as a prebuilt binary from the github.com/docker/clipboardbridge release
# pinned by CLIPBOARD_BRIDGE_VERSION; SHA256SUMS verification is mandatory.
ARG TARGETARCH
ARG CLIPBOARD_BRIDGE_VERSION
RUN <<EOF
set -euxo pipefail
base="https://github.com/docker/clipboardbridge/releases/download/${CLIPBOARD_BRIDGE_VERSION}"
asset="clipboard-bridge-linux-${TARGETARCH}"
tmp=$(mktemp -d)
curl -fsSL "${base}/${asset}"     -o "${tmp}/${asset}"
curl -fsSL "${base}/SHA256SUMS"   -o "${tmp}/SHA256SUMS"
(cd "${tmp}" && grep " ${asset}\$" SHA256SUMS | sha256sum -c -)
install -m 0755 "${tmp}/${asset}" /usr/local/bin/clipboard-bridge
rm -rf "${tmp}"
EOF

FROM base AS tools-minimal

################################
# Tools for the minimal images #
################################

USER root
RUN <<EOF
set -euxo pipefail
apt-get update
apt-get install -yy --no-install-recommends \
    bubblewrap \
    dnsutils \
    docker-buildx-plugin \
    docker-ce-cli \
    docker-compose-plugin \
    git \
    gh \
    jq \
    less \
    lsof \
    make \
    openssh-client \
    procps \
    psmisc \
    ripgrep \
    rsync \
    socat \
    sudo \
    tini \
    unzip

apt-get clean
rm -rf /var/lib/apt/lists/*

EOF
USER agent

# Use tini as PID 1 so processes launched via `docker exec` (e.g. `sbx exec`)
# get properly reaped instead of accumulating as zombies. Declared here so
# every downstream template inherits it without each stage repeating it. The
# container's CMD (`sleep infinity` when sbx runs it, or the CMD below when
# run standalone) is appended to this ENTRYPOINT by Docker.
ENTRYPOINT ["tini", "--"]

FROM tools-minimal AS tools

#############################
# Tools for the full images #
#############################

USER root
RUN <<EOF
set -euxo pipefail
apt-get update
apt-get install -yy --no-install-recommends \
    bc \
    build-essential \
    default-jdk-headless \
    golang \
    man-db \
    nodejs \
    npm \
    python3 \
    python3-pip

apt-get clean
rm -rf /var/lib/apt/lists/*

EOF
USER agent

#########################################
# Base for Docker-in-Docker variants    #
# Installs docker-ce once so the 10     #
# -docker targets don't each run their  #
# own apt-get against the same mirror.  #
#########################################
FROM tools AS tools-docker
USER root
RUN <<EOF
set -euxo pipefail
apt-get update
apt-get install -yy --no-install-recommends \
    containerd.io \
    docker-ce

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
USER agent

FROM tools-docker AS shell
# Configure a cleaner shell prompt: user@sandbox:dirname$
# Uses \W (directory basename) instead of \w (full path) for readability
# Ensure login shells also source .bashrc so the prompt applies with "bash -l".
RUN <<EOF
set -ex
echo 'PS1='"'"'\u@\h:\W\$ '"'" >> /home/agent/.bashrc
printf '\n# Source .bashrc for login shells\nif [ -f ~/.bashrc ]; then . ~/.bashrc; fi\n' >> /home/agent/.bash_profile
chown agent:agent /home/agent/.bashrc /home/agent/.bash_profile
EOF

# The stages above clear /var/lib/apt/lists, so refresh the index here and
# `apt-get install` works in a fresh sandbox without a refresh first. CI
# rebuilds nightly, so the index `latest` carries is at most a day old.
USER root
RUN apt-get update -qq -y
USER agent

# A request to the runtime, not a description of the image: privileged mode,
# a block volume at /var/lib/docker and dockerd at boot.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as an agent identifier and surfaces it as an image's
# Agent, so it names this kit.
LABEL com.docker.sandboxes.flavor="shell"

# Informational: what this image was built from.
ARG UBUNTU_VERSION
LABEL com.docker.sandboxes.base="ubuntu:${UBUNTU_VERSION}"

# Bare `bash`, with none of the kit's own arguments: the kit supplies `-l`, so
# a plain `docker run -it` of this image gets a non-login interactive shell.
CMD [ "bash" ]
