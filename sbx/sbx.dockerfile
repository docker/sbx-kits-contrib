# syntax=docker/dockerfile:1
# Installs the sbx release tarball at build time into a scratch overlay.
ARG SBX_VERSION=0.51.0
FROM debian:trixie-slim AS build
ARG SBX_VERSION
ARG TARGETARCH
ADD https://github.com/docker/sbx-releases/releases/download/v${SBX_VERSION}/DockerSandboxes-linux-${TARGETARCH}.tar.gz /tmp/sbx.tar.gz
RUN tar xzf /tmp/sbx.tar.gz -C /tmp \
 && PREFIX=/out/usr/local /tmp/docker-sbx/install.sh \
 && /out/usr/local/bin/sbx version | grep -q "^sbx version v${SBX_VERSION} "

FROM scratch
COPY --from=build /out /
ENTRYPOINT ["sbx"]
CMD ["version"]
