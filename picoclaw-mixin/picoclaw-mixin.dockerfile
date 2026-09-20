# syntax=docker/dockerfile:1.7
# PicoClaw as an overlay.
#
# This is the clean overlay shape, and the kit earns it: PicoClaw is one Go
# static binary fetched by exact tag and checked against a hardcoded digest.
# Nothing needs relocating, so the build stage only has to land the artifacts
# under /out at the absolute paths they will occupy once the overlay is
# composed, and the final stage is a scratch copy of that tree.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg, holding `0.2.9`: a v3 version carries no `v`
# prefix, so the upstream tag is spelled `v${PICOCLAW_VERSION}` below.
ARG PICOCLAW_VERSION=0.2.9
ARG TARGETARCH

USER root

# The digests are the workload kit's, unchanged. Bumping PICOCLAW_VERSION is
# a deliberate edit that must bring new digests with it -- there is no
# upstream checksums file to re-derive them from, so recompute both with
# `sha256sum` against the new release's own assets, here and in ../picoclaw.
RUN set -euo pipefail; \
    case "${TARGETARCH}" in \
      amd64) arch=x86_64; sha256=7e658f320e9d63779f4d1c32ea64bf474d903bc91d41afdc79c8f0572ab936b4 ;; \
      arm64) arch=arm64; sha256=a8989b1a409ec995cde454a17222d00eb5b0c9dbda08213e2f82d22526023c9f ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/picoclaw.tar.gz \
      "https://github.com/sipeed/picoclaw/releases/download/v${PICOCLAW_VERSION}/picoclaw_Linux_${arch}.tar.gz"; \
    echo "${sha256}  /tmp/picoclaw.tar.gz" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -xzf /tmp/picoclaw.tar.gz -C /out/usr/local/bin picoclaw; \
    rm /tmp/picoclaw.tar.gz; \
    chmod 0755 /out/usr/local/bin/picoclaw; \
    /out/usr/local/bin/picoclaw version

# The kit's own scripts and seed config.
#
# MIGRATION NOTE: this tree is a copy of ../picoclaw/files/, not a reference
# to it. A kit's build context is rooted at its own descriptor's directory and
# may not escape it (SPEC-v3 §4), so a sibling kit's assets are unreachable
# from here. The two must move together -- see this kit's README. Copied
# without an exec bit, as the workload copies them, because
# picoclaw-anthropic-auth.sh is invoked through `sh`.
# No --chown here: BuildKit applies it to every parent it creates, which
# stamps uid 1000 onto /out/home and hands /home away on every base this
# composes onto. The `chown -R /out/home/agent` below starts one level too
# deep to undo that, so the copy leaves parents root-owned and the chown
# owns exactly the agent home and its contents.
COPY files/home/ /out/home/agent/

# picoclaw-start.sh additionally lands as a 0755 launcher on PATH. A mixin
# sets no entrypoint, so this is how a user gets the workload's launch
# behaviour -- resolve the credential, bring the gateway up if it is not
# already answering, then exec the agent CLI -- in one word.
RUN install -m 0755 /out/home/agent/.local/bin/picoclaw-start.sh /out/usr/local/bin/picoclaw-start \
 && chown -R 1000:1000 /out/home/agent

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead.
COPY <<'EOF' /out/etc/profile.d/picoclaw-env.sh
export PICOCLAW_GATEWAY_HOST=0.0.0.0
export PICOCLAW_HOME=/home/agent/.picoclaw
EOF

# The overlay: one binary, the kit's scripts and its seed config, landing on
# any base. No ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
