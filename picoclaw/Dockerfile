# syntax=docker/dockerfile:1.7
# Base image for the `picoclaw` sandbox kit.
#
# PicoClaw is a single ~10MB static release binary, so this pre-bake buys
# only one thing: the release download and its SHA256 verification move to
# build time, off this kit's *runtime* network allowlist -- the engine
# enforces one allowlist per sandbox and cannot distinguish a build-time
# fetch from one the running agent might make.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# hermes-agent/pi/openclaw/kiro/copilot.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# No -docker variant and no start-docker label: PicoClaw is an agent CLI plus
# a channel gateway, neither of which touches a container engine.

# Pinned deliberately, not floated to "latest": the binary is fetched once at
# build time by exact tag with a hardcoded per-arch digest, so a nightly
# rebuild with no version bump reproduces the same bytes. Bumping
# PICOCLAW_VERSION is a deliberate edit that must bring new digests with it --
# there is no upstream checksums file to re-derive them from, so recompute
# both with `sha256sum` against the new release's own assets.
ARG PICOCLAW_VERSION=v0.2.9

# TARGETARCH is buildx's per-platform arg: building --platform
# linux/amd64,linux/arm64 runs this stage once per platform with TARGETARCH
# set to that platform, not the builder host's own -- unlike the kit's old
# `case "$(uname -m)" ...` install command, which only ever saw the sandbox
# it was running in. The two digests are unchanged from the kit's previous
# create-time install command; only where they run has moved.
USER root
ARG TARGETARCH
RUN set -euo pipefail; \
    case "${TARGETARCH}" in \
      amd64) arch=x86_64; sha256=7e658f320e9d63779f4d1c32ea64bf474d903bc91d41afdc79c8f0572ab936b4 ;; \
      arm64) arch=arm64; sha256=a8989b1a409ec995cde454a17222d00eb5b0c9dbda08213e2f82d22526023c9f ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/picoclaw.tar.gz \
      "https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/picoclaw_Linux_${arch}.tar.gz"; \
    echo "${sha256}  /tmp/picoclaw.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/picoclaw.tar.gz -C /usr/local/bin picoclaw; \
    rm /tmp/picoclaw.tar.gz; \
    chmod 0755 /usr/local/bin/picoclaw; \
    picoclaw version

# COPY, not a reference to the kit's files/ tree: this is what makes the
# image's own CMD work when the image is run directly (docker run, or before
# the kit's setup.startup hooks have ever executed), independent of sbx. The
# kit's sandbox.entrypoint in spec.yaml points at the files/home/ copy of
# this same script instead, so a fix to it reaches an existing sandbox on
# its next create without waiting on an image republish. Standalone, the
# credential-resolver call inside it targets a config.json that only exists
# once the kit's files/ tree lands, so it is a harmless no-op there.
COPY --chmod=0755 files/home/.local/bin/picoclaw-start.sh /usr/local/bin/picoclaw-start

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "picoclaw".
LABEL com.docker.sandboxes.flavor="picoclaw"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/picoclaw-start"]
