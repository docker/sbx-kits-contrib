# syntax=docker/dockerfile:1.7
# ZeroClaw as an overlay.
#
# This is the clean overlay shape, and the kit earns it: ZeroClaw is one Rust
# static binary fetched by exact tag and checked against a hardcoded digest.
# Nothing needs relocating, so the build stage only has to land the artifacts
# under /out at the absolute paths they will occupy once the overlay is
# composed, and the final stage is a scratch copy of that tree.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg, holding `0.8.0`: a v3 version carries no `v`
# prefix, so the upstream tag is spelled `v${ZEROCLAW_VERSION}` below.
ARG ZEROCLAW_VERSION=0.8.0
ARG TARGETARCH

USER root

# The digests are the workload kit's, unchanged: this repository's own,
# computed from each asset at ZEROCLAW_VERSION and cross-checked against
# upstream's SHA256SUMS for that tag. Bumping the version is a deliberate edit
# that must re-verify both, here and in ../zeroclaw.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) target=x86_64-unknown-linux-gnu; sha256=b3a3349971fc2e030b80f95999ae3fb671dc8d7af2ebeabedd7ea176c6182b64 ;; \
      arm64) target=aarch64-unknown-linux-gnu; sha256=5faf556fd5e5655761c71bd02121384cc7371f936519b25cb2f1be976f2cf540 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/zeroclaw.tar.gz \
      "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}/zeroclaw-${target}.tar.gz"; \
    echo "${sha256}  /tmp/zeroclaw.tar.gz" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -xzf /tmp/zeroclaw.tar.gz -C /out/usr/local/bin zeroclaw; \
    rm /tmp/zeroclaw.tar.gz; \
    chmod 0755 /out/usr/local/bin/zeroclaw; \
    /out/usr/local/bin/zeroclaw --version

# The kit's own scripts and seed config.
#
# MIGRATION NOTE: this tree is a copy of ../zeroclaw/files/, not a reference
# to it. A kit's build context is rooted at its own descriptor's directory and
# may not escape it (SPEC-v3 §4), so a sibling kit's assets are unreachable
# from here. The two must move together -- see this kit's README. Copied
# without an exec bit, as the workload copies them, because
# zeroclaw-anthropic-key.sh is invoked through `sh`.
COPY --chown=agent:agent files/home/ /out/home/agent/

# zeroclaw-start.sh additionally lands as a 0755 launcher on PATH. A mixin
# sets no entrypoint, and unlike picoclaw this kit's daemon is started by the
# entrypoint rather than by a hook -- so this launcher is what brings the
# gateway up on the published port.
RUN install -m 0755 /out/home/agent/.local/bin/zeroclaw-start.sh /out/usr/local/bin/zeroclaw-start \
 && chown -R 1000:1000 /out/home/agent

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead. The double underscore is ZeroClaw's
# nesting separator: this is the [gateway] table's `host` field.
COPY <<'EOF' /out/etc/profile.d/zeroclaw-env.sh
export ZEROCLAW_gateway__host=0.0.0.0
EOF

# The overlay: one binary, the kit's scripts and its seed config, landing on
# any base. No ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
