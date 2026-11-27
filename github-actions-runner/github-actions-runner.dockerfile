# syntax=docker/dockerfile:1
# The build stage only downloads and verifies the archive; a small pinned Debian is enough.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS build

ARG TARGETARCH
ARG RUNNER_VERSION
ARG RUNNER_SHA256_X64
ARG RUNNER_SHA256_ARM64

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) arch=x64; sha256="$RUNNER_SHA256_X64" ;; \
      arm64) arch=arm64; sha256="$RUNNER_SHA256_ARM64" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz"; \
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o /tmp/actions-runner.tar.gz; \
    echo "$sha256  /tmp/actions-runner.tar.gz" | sha256sum -c -; \
    mkdir -p /out/opt/actions-runner; \
    tar -xzf /tmp/actions-runner.tar.gz -C /out/opt/actions-runner; \
    test -x /out/opt/actions-runner/bin/installdependencies.sh; \
    chown -R 1000:1000 /out/opt/actions-runner; \
    chmod -R a+rX /out/opt/actions-runner; \
    rm /tmp/actions-runner.tar.gz

FROM scratch
COPY --from=build /out/ /
