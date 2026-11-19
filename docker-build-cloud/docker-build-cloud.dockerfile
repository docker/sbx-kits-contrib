# syntax=docker/dockerfile:1
# The kit's one file: the helper that serves the Docker Hub shim, writes the
# placeholder Docker login and checks itself. See files/helper.py for what it
# does and why, and README.md for the design.
#
# It is plain Python on the standard library, so there is nothing to download
# and nothing to pin: no network is used here, at build or at run.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker

# Staged on a fresh supported base and run as the runtime user with no
# network, which is how it will run in a sandbox. The self-test starts its
# own loopback servers and talks to nothing else.
FROM ${BASE_IMAGE} AS verify
USER root
COPY --chown=0:0 --chmod=0755 files/helper.py /usr/local/lib/docker-build-cloud/helper.py
USER agent
RUN --network=none python3 /usr/local/lib/docker-build-cloud/helper.py self-test

# The overlay is exported from the verify stage, not from the build context,
# so BuildKit cannot skip the self-test: no other path leads to these files.
# Under /usr/local/lib rather than the agent's home, which on a composed base
# may be a mounted volume that would cover anything an overlay put there.
FROM scratch
COPY --from=verify /usr/local/lib/docker-build-cloud /usr/local/lib/docker-build-cloud
