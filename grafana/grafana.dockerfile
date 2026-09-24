# syntax=docker/dockerfile:1
# mcp-grafana is a pinned native binary, so v3 can carry it in the mixin
# overlay instead of downloading it for every sandbox. The Python client stays
# a lifecycle hook because it must install against the composed base's Python.
FROM dhi.io/debian-base:trixie-dev AS build
ARG TARGETARCH

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) archive_arch=x64 ;; \
      arm64) archive_arch=arm64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    mkdir -p /out/home/agent/.local/bin; \
    curl -fsSL -o /tmp/mcp-grafana.tgz \
      "https://github.com/grafana/mcp-grafana/releases/download/v1.0.0/linux.${archive_arch}.grafana.tar.gz"; \
    tar -xzf /tmp/mcp-grafana.tgz -C /out/home/agent/.local/bin mcp-grafana; \
    chmod 0755 /out/home/agent/.local/bin/mcp-grafana

# The v2 kit's files/ tree ships these runbooks. Create /home as root-owned and
# normalize only /home/agent to uid 1000, preserving overlay ownership rules.
COPY files/home/runbooks /out/home/agent/runbooks
RUN chown 0:0 /out/home \
 && chown -R 1000:1000 /out/home/agent

# The overlay: no entrypoint, so the base workload keeps its launch command.
FROM scratch
COPY --from=build /out /
ENV GRAFANA_URL=http://host.docker.internal:3000 \
    NO_PROXY=localhost,127.0.0.1,host.docker.internal \
    no_proxy=localhost,127.0.0.1,host.docker.internal
