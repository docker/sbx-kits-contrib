# syntax=docker/dockerfile:1.7
# The zeroclaw workload's content. This is the v2 kit's Dockerfile: v2
# published it as docker.io/sbx/zeroclaw-image:latest and pointed
# `sandbox.image` at the result, while a v3 workload's layers *are* the root
# filesystem -- so the intermediate publish disappears and this recipe builds
# the kit directly. v2's environment.variables and sandbox.entrypoint land at
# the bottom, in the image config that already owns runtime config.
#
# ZeroClaw is a single ~10MB static release binary, so the pre-bake buys one
# thing: the release download and its integrity check stay at build time, off
# this kit's *runtime* network allowlist.
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
#
# The kit's `version` arg is handed here as this build arg, and it holds
# `0.8.0`: a v3 version carries no `v` prefix, so the upstream tag is spelled
# `v${ZEROCLAW_VERSION}` at the point of use below.
ARG ZEROCLAW_VERSION=0.8.0

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
      "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}/zeroclaw-${target}.tar.gz"; \
    echo "${sha256}  /tmp/zeroclaw.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/zeroclaw.tar.gz -C /usr/local/bin zeroclaw; \
    rm /tmp/zeroclaw.tar.gz; \
    chmod 0755 /usr/local/bin/zeroclaw; \
    zeroclaw --version

# The 0755 copy the v2 image shipped so a plain `docker run` worked before the
# kit's files/ tree existed. It backed the v2 CMD; the ENTRYPOINT below is
# what launches the daemon now, and this stays as the shell-callable name.
COPY --chmod=0755 files/home/.local/bin/zeroclaw-start.sh /usr/local/bin/zeroclaw-start

# The kit's files/home/ tree. v2's artifact loader copied it into /home/agent/
# at sandbox create; v3 has no implicit files/ convention, so the recipe lands
# it. --chmod=0644 reproduces the mode the loader left, which is why the
# ENTRYPOINT below invokes the script through `sh` rather than exec'ing it --
# keeping v2's sandbox.entrypoint spelling exactly. config.toml carries the
# `__ANTHROPIC_API_KEY__` placeholder the startup hook substitutes, and comes
# back fresh from this layer on every create, exactly as the v2 copy did.
COPY --chown=agent:agent --chmod=0644 \
     files/home/.local/bin/zeroclaw-start.sh \
     files/home/.local/bin/zeroclaw-anthropic-key.sh \
     /home/agent/.local/bin/
COPY --chown=agent:agent --chmod=0644 \
     files/home/.zeroclaw/config.toml \
     /home/agent/.zeroclaw/config.toml

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "zeroclaw".
LABEL com.docker.sandboxes.flavor="zeroclaw"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
# The double underscore is ZeroClaw's nesting separator: this is the
# [gateway] table's `host` field.
ENV ZEROCLAW_gateway__host=0.0.0.0

USER agent
WORKDIR /home/agent
# v2's sandbox.entrypoint. Setting ENTRYPOINT also clears the CMD inherited
# from the base (and replaces the v2 image's own CMD, which named the same
# script by its /usr/local/bin copy), so nothing is appended to it.
ENTRYPOINT ["sh", "/home/agent/.local/bin/zeroclaw-start.sh"]
