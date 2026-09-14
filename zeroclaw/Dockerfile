# syntax=docker/dockerfile:1.7
# Base image for the `zeroclaw` sandbox kit.
#
# ZeroClaw is a single ~10MB static release binary, so this pre-bake buys
# only one thing: the release download (and its integrity check) move to
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

# No -docker variant and no start-docker label: ZeroClaw's tool calls already
# run inside the sandbox microVM, and config.toml sets sandbox_backend =
# "none" because its own Landlock/Bubblewrap backends aren't available
# in-container either way -- there is no Docker-shaped need here.

# Pinned deliberately, not floated to "latest": the binary is fetched once at
# build time by exact tag, so a nightly rebuild with no version bump
# reproduces the same bytes instead of silently picking up a new release.
# Bumping this is a deliberate edit -- re-verify both digests below against
# the release's own SHA256SUMS asset (published for every tag from v0.8.0 on)
# before changing them.
ARG ZEROCLAW_VERSION=v0.8.0

# TARGETARCH is buildx's per-platform arg: building --platform
# linux/amd64,linux/arm64 runs this stage once per platform with TARGETARCH
# set to that platform, not the builder host's own -- unlike the kit's old
# `case "$(uname -m)" ...` install command, which only ever saw the sandbox
# it was running in.
#
# The two digests are this repository's own, computed from each asset at
# ZEROCLAW_VERSION and cross-checked against upstream's SHA256SUMS for that
# tag -- ZeroClaw's release download previously shipped with no integrity
# check at all. A hardcoded digest here (rather than fetching SHA256SUMS at
# build time and trusting whatever it says) still catches a same-tag asset
# swap after the fact, since re-publishing SHA256SUMS under the unchanged tag
# would go unnoticed the other way.
USER root
ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) target=x86_64-unknown-linux-gnu; sha256=b3a3349971fc2e030b80f95999ae3fb671dc8d7af2ebeabedd7ea176c6182b64 ;; \
      arm64) target=aarch64-unknown-linux-gnu; sha256=5faf556fd5e5655761c71bd02121384cc7371f936519b25cb2f1be976f2cf540 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/zeroclaw.tar.gz \
      "https://github.com/zeroclaw-labs/zeroclaw/releases/download/${ZEROCLAW_VERSION}/zeroclaw-${target}.tar.gz"; \
    echo "${sha256}  /tmp/zeroclaw.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/zeroclaw.tar.gz -C /usr/local/bin zeroclaw; \
    rm /tmp/zeroclaw.tar.gz; \
    chmod 0755 /usr/local/bin/zeroclaw; \
    zeroclaw --version

# COPY, not a reference to the kit's files/ tree: this is what makes the
# image's own CMD work when the image is run directly (docker run, or before
# the kit's setup.startup hook has ever executed), independent of sbx. The
# kit's sandbox.entrypoint in spec.yaml points at the files/home/ copy of
# this same script instead, so a fix to it reaches an existing sandbox on
# its next create without waiting on an image republish. Standalone, the
# credential-resolver call inside it targets a config.toml that only exists
# once the kit's files/ tree lands, so it is a harmless no-op there -- the
# daemon still starts, on whatever config ZeroClaw finds or creates itself.
COPY --chmod=0755 files/home/.local/bin/zeroclaw-start.sh /usr/local/bin/zeroclaw-start

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "zeroclaw".
LABEL com.docker.sandboxes.flavor="zeroclaw"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/zeroclaw-start"]
