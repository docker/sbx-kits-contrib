# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
#
# (The ENV GITGUARDIAN_API_KEY below is a deliberate non-secret placeholder -
# "proxy-managed" - not a credential; the real key lives on the host and is
# injected by the proxy on the wire. The linter rule does not know that, so we
# skip it rather than let a known-safe sentinel trip every build.)
#
# Overlay recipe for the GitGuardian (ggshield) mixin.
#
# ggshield ships here as a LAYER instead of a v2 install hook. It is a pinned,
# digest-verified release tarball with nothing create-time about it, so baking
# it buys four things: no per-sandbox-create download, digest-pinned and
# scannable content, a failure that surfaces at publish instead of in a user's
# sandbox, and - the one that shows up in the permission surface - the v2
# install-phase network grant (github.com + the two object stores) disappears
# entirely. The descriptor now opens the network only at runtime, for
# api.gitguardian.com.
#
# The release is a self-contained PyInstaller bundle (a launcher plus an
# _internal/ tree). It is fully relocatable - files under /opt plus one symlink
# on PATH - so it travels cleanly in a `scratch` overlay onto any base.
#
# The AI-hook wiring (`ggshield machine setup`) does NOT live here - it merges
# into the agent's own ~/.claude/settings.json and so stays a create-time
# lifecycle hook in gitguardian.yaml.
#
# To bump: change GGSHIELD_VERSION and both per-arch SHA256 values below
# (sha256sum of each release tarball), and keep the `provides:` version in
# gitguardian.yaml in lockstep.

ARG GGSHIELD_VERSION=1.53.0

# Build stage: download + verify + extract on a throwaway glibc base that has
# the tools (curl, tar, sha256sum) and the right libc to smoke-test the binary.
# Nothing from this stage is shipped - only /out is copied into the overlay.
# buildx runs this stage once per target platform, so TARGETARCH selects the
# matching release asset on each.
FROM debian:bookworm-slim AS build
ARG GGSHIELD_VERSION
ARG TARGETARCH

RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    case "$TARGETARCH" in \
      amd64) \
        SLUG="x86_64-unknown-linux-gnu"; \
        SHA256="234d1a62ea7b769695c7e5aee8f29e9d0069cd09b4e5b67493d3b529abb44e4a" ;; \
      arm64) \
        SLUG="aarch64-unknown-linux-gnu"; \
        SHA256="097616513fe7a4f25831a464b8968b124af32d274e2ce006e388800605696b20" ;; \
      *) \
        echo "unsupported target arch: $TARGETARCH (expected amd64 or arm64)" >&2; \
        exit 1 ;; \
    esac; \
    DIRNAME="ggshield-${GGSHIELD_VERSION}-${SLUG}"; \
    TARBALL="${DIRNAME}.tar.gz"; \
    URL="https://github.com/GitGuardian/ggshield/releases/download/v${GGSHIELD_VERSION}/${TARBALL}"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/ggshield.tgz "$URL"; \
    echo "${SHA256}  /tmp/ggshield.tgz" | sha256sum -c -; \
    mkdir -p /out/opt /out/usr/local/bin; \
    # --no-same-owner: the release tarball carries the GitGuardian build uid;
    # extracting under it would ship a foreign owner in the overlay. Forcing
    # root here (plus the chown below) keeps every overlay file 0/0.
    tar --no-same-owner -C /out/opt -xzf /tmp/ggshield.tgz; \
    mv "/out/opt/${DIRNAME}" /out/opt/ggshield; \
    # Absolute target: resolves at runtime on the composed base, not here.
    ln -sf /opt/ggshield/ggshield /out/usr/local/bin/ggshield; \
    rm -f /tmp/ggshield.tgz; \
    chown -R 0:0 /out; \
    # A pinned provide is a claim about content - make the build enforce it.
    /out/opt/ggshield/ggshield --version; \
    /out/opt/ggshield/ggshield --version | grep -q "${GGSHIELD_VERSION}"

# The overlay: a scratch root carrying only ggshield's tree and its launcher
# symlink. Lands on any base at compose time.
FROM scratch
COPY --from=build /out /

# gitguardian is a custom (non-registry) service, so sbx does NOT auto-export
# the apiKey sentinel into the container - it only sets SBX_CRED_GITGUARDIAN_MODE.
# ggshield refuses to run when GITGUARDIAN_API_KEY is unset, so we materialize
# the sentinel ourselves. The value is a placeholder; the proxy swaps in the
# real key on outbound api.gitguardian.com requests, so the real token never
# enters the sandbox. ENV on the final stage merges into the composed image.
ENV GITGUARDIAN_API_KEY=proxy-managed
