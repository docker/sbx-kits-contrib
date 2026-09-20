# syntax=docker/dockerfile:1.7
# The picoclaw workload's content. This is the v2 kit's Dockerfile: v2
# published it as docker.io/sbx/picoclaw-image:latest and pointed
# `sandbox.image` at the result, while a v3 workload's layers *are* the root
# filesystem -- so the intermediate publish disappears and this recipe builds
# the kit directly. v2's environment.variables and sandbox.entrypoint land at
# the bottom, in the image config that already owns runtime config.
#
# PicoClaw is a single ~10MB static release binary, so the pre-bake buys one
# thing: the release download and its SHA256 verification stay at build time,
# off this kit's *runtime* network allowlist.
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
# rebuild with no version bump reproduces the same bytes. Bumping the pin is a
# deliberate edit that must bring new digests with it -- there is no upstream
# checksums file to re-derive them from, so recompute both with `sha256sum`
# against the new release's own assets.
#
# The kit's `version` arg is handed here as this build arg, and it holds
# `0.2.9`: a v3 version carries no `v` prefix, so the upstream tag is spelled
# `v${PICOCLAW_VERSION}` at the point of use below.
ARG PICOCLAW_VERSION=0.2.9

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
      "https://github.com/sipeed/picoclaw/releases/download/v${PICOCLAW_VERSION}/picoclaw_Linux_${arch}.tar.gz"; \
    echo "${sha256}  /tmp/picoclaw.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/picoclaw.tar.gz -C /usr/local/bin picoclaw; \
    rm /tmp/picoclaw.tar.gz; \
    chmod 0755 /usr/local/bin/picoclaw; \
    picoclaw version

# The 0755 copy the v2 image shipped so a plain `docker run` worked before the
# kit's files/ tree existed. It backed the v2 CMD; the ENTRYPOINT below is
# what launches the agent now, and this stays as the shell-callable name.
COPY --chmod=0755 files/home/.local/bin/picoclaw-start.sh /usr/local/bin/picoclaw-start

# The kit's files/home/ tree. v2's artifact loader copied it into /home/agent/
# at sandbox create; v3 has no implicit files/ convention, so the recipe lands
# it. --chmod=0644 reproduces the mode the loader left, which is why the
# ENTRYPOINT below invokes the script through `sh` rather than exec'ing it --
# keeping v2's sandbox.entrypoint spelling exactly. config.json carries the
# `__ANTHROPIC_API_KEY__` placeholder the startup hook substitutes, and comes
# back fresh from this layer on every create, exactly as the v2 copy did.
COPY --chown=agent:agent --chmod=0644 \
     files/home/.local/bin/picoclaw-start.sh \
     files/home/.local/bin/picoclaw-anthropic-auth.sh \
     /home/agent/.local/bin/
COPY --chown=agent:agent --chmod=0644 \
     files/home/.picoclaw/config.json \
     /home/agent/.picoclaw/config.json

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "picoclaw".
LABEL com.docker.sandboxes.flavor="picoclaw"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
ENV PICOCLAW_GATEWAY_HOST=0.0.0.0 \
    PICOCLAW_HOME=/home/agent/.picoclaw

USER agent
WORKDIR /home/agent
# v2's sandbox.entrypoint. Setting ENTRYPOINT also clears the CMD inherited
# from the base (and replaces the v2 image's own CMD, which named the same
# script by its /usr/local/bin copy), so nothing is appended to it.
ENTRYPOINT ["sh", "/home/agent/.local/bin/picoclaw-start.sh"]
