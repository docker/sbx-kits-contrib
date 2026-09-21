# syntax=docker/dockerfile:1.7
# Trivy as an overlay.
#
# This is the clean overlay shape, and the kit earns it: trivy is one Go
# static binary. Nothing needs relocating, so the build stage only has to land
# the binary under /out at the absolute path it will occupy once the overlay
# is composed, and the final stage is a scratch copy of that tree.
#
# MIGRATION NOTE: the workload kit installs trivy from a `setup.install` hook
# at sandbox create; here the same pinned, digest-verified download runs at
# *build* time instead. That is what an overlay is, and it is why this kit's
# descriptor declares no install phase: the release hosts are contacted by the
# builder, not by the sandbox. The version and both digests are the workload's
# hook verbatim -- keep them in step with ../trivy/trivy.yaml.
#
# Why not the official `install.sh`: that pattern (curl|sh) is exactly what
# TeamPCP weaponized in March 2026 against tag-rewriteable references. The
# release is pinned by version AND SHA256, in the kit, in git.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

ARG TRIVY_VERSION=0.70.0
ARG TARGETARCH

USER root

# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever
# see the one sandbox it ran in.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        tarball="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
        sha256=8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9 ;; \
      arm64) \
        tarball="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
        sha256=2f6bb988b553a1bbac6bdd1ce890f5e412439564e17522b88a4541b4f364fc8d ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/trivy.tgz \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${tarball}"; \
    echo "${sha256}  /tmp/trivy.tgz" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -C /out/usr/local/bin -xzf /tmp/trivy.tgz trivy; \
    rm /tmp/trivy.tgz; \
    chmod 0755 /out/usr/local/bin/trivy; \
    # The release tarball records the publisher's CI uid, and tar preserves it:
    # as image content on an unknown base that id may be a real account, and a
    # file's owner can rewrite it whatever its mode says.
    chown 0:0 /out/usr/local/bin/trivy; \
    /out/usr/local/bin/trivy --version

# The overlay: one binary, landing on any base. No ENTRYPOINT -- the base
# workload's launch command stays, and the user runs `trivy` from the shell.
FROM scratch
COPY --from=build /out /
