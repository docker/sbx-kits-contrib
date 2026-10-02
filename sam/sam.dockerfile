# syntax=docker/dockerfile:1
# Copies sam-node out of SAM's own release image rather than downloading a
# tarball: the image is multi-arch and digest-addressed, so no checksum list.
ARG SAM_VERSION=v0.1.0-rc.8
FROM ghcr.io/google/sam-node:${SAM_VERSION} AS sam

FROM scratch
COPY --from=sam /sam-node /usr/local/bin/sam-node
COPY --chmod=0755 files/usr/local/lib/sam/ /usr/local/lib/sam/
