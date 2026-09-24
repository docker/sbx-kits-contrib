# syntax=docker/dockerfile:1

# MIGRATION NOTE: v2 downloaded the Mend CLI from this same unversioned vendor
# endpoint in a create-time hook. A v3 mixin can carry content, so the portable
# binary is downloaded once at publish and shipped as a root-owned overlay.
#
# The URL exposes no version selector, so this recipe deliberately makes no
# `provides: mend@...` claim. Publishing a pinned capability for floating
# content would be less accurate than publishing no capability.
FROM docker/sandbox-templates:shell-docker AS build

USER root
RUN set -eux; \
    case "$(uname -m)" in \
      aarch64|arm64) plat=linux_arm64 ;; \
      *) plat=linux_amd64 ;; \
    esac; \
    mkdir -p /out/usr/local/bin; \
    curl -fsSL "https://downloads.mend.io/cli/$plat/mend" \
      -o /out/usr/local/bin/mend; \
    chmod 0755 /out/usr/local/bin/mend; \
    test -x /out/usr/local/bin/mend

# The overlay: one architecture-matched binary, landing on any workload.
FROM scratch
COPY --from=build /out /
