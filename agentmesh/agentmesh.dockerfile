# syntax=docker/dockerfile:1
# Copies agentmesh-node out of Agent Mesh's own image rather than downloading a
# tarball: the image is digest-addressed and multi-arch, so no checksum list.
ARG AGENTMESH_VERSION=v0.1.0
FROM ghcr.io/google/agentmesh-node:${AGENTMESH_VERSION} AS agentmesh

FROM scratch
COPY --from=agentmesh /agentmesh-node /usr/local/bin/agentmesh-node
COPY --chmod=0755 files/usr/local/lib/agentmesh/ /usr/local/lib/agentmesh/
