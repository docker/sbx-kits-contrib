# syntax=docker/dockerfile:1

# Base image for the `vibe` sandbox kit: the shell-docker template with
# Mistral Vibe installed from PyPI.
#
# Built and pushed as docker.io/sbx/vibe-image by build-and-publish-kits.yml
# (see ../PUBLISHING.md). The base is a floating tag and Vibe is installed from
# a `latest` channel, which is why CI also rebuilds on a schedule.
#
# Build it locally the way the test scripts do:
#   docker build -t docker.io/sbx/vibe-image:latest ./vibe
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# PyPI version of mistral-vibe: "latest", or an exact number such as 2.25.0 to
# pin the image to a known release.
ARG VIBE_VERSION=latest

# uv ships with the template at /usr/local/bin/uv, and `uv tool install` puts
# the executables in ~/.local/bin, which is already on the template's PATH --
# so `sandbox.entrypoint` can stay the bare name `vibe`.
USER agent
RUN set -ex; \
    if [ "${VIBE_VERSION}" = "latest" ]; then SPEC="mistral-vibe"; else SPEC="mistral-vibe==${VIBE_VERSION}"; fi; \
    uv tool install "${SPEC}"; \
    vibe --version

# Requests Docker-in-Docker from the runtime. Inherited from the base image,
# but re-declared so the value is owned here rather than depending on
# inheritance from an image this repository does not own.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as the image's agent identifier and surfaces it in the API,
# so it must be the kit's own name -- left inherited it would read
# "shell-docker" and sbx would report this image's agent as that.
LABEL com.docker.sandboxes.flavor="vibe"

# Informational only. Worth setting because the base is a floating tag rebuilt
# nightly: this is the one place the produced image records what it was built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

WORKDIR /home/agent

# The kit sets the real entrypoint (spec.yaml); this only applies to a plain
# `docker run` of the image, outside sbx.
CMD ["vibe"]
