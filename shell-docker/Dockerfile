# syntax=docker/dockerfile:1

# Base image for the `shell-docker` sandbox kit: the `shell` kit's image plus a
# Docker engine. The toolchain, the `agent` user, the Docker CLI and tini come
# from the base, which this repository builds and publishes too, so the two
# images differ by exactly the engine layer below.
#
# Parameterised so a build can be aimed at a specific base digest without
# editing this file. Nothing in this repository passes the arg, so the default
# is what ships. The base is a rolling tag: build-and-publish-kits.yml rebuilds
# this image in the same run as the shell image, right after it.
ARG BASE_IMAGE=docker.io/sbx/shell-image:latest
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

USER root
RUN <<EOF
set -euxo pipefail
apt-get update
apt-get install -yy --no-install-recommends \
    containerd.io \
    docker-ce

# Only the package cache is cleared. The base ships a refreshed apt index so
# `apt-get install` works in a fresh sandbox, and the update above keeps it so.
apt-get clean
EOF
USER agent

# A request to the runtime, not a description of the image: privileged mode,
# a block volume at /var/lib/docker and dockerd at boot.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as an agent identifier and surfaces it as an image's
# Agent, so it names this kit. Left inherited it would read "shell".
LABEL com.docker.sandboxes.flavor="shell-docker"

# Informational: what this image was built from.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Bare `bash`, with none of the kit's own arguments: the kit supplies `-l`, so
# a plain `docker run -it` of this image gets a non-login interactive shell.
CMD [ "bash" ]
