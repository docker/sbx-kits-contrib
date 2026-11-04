# syntax=docker/dockerfile:1
#
# Overlay recipe for the PANW endpoint enforcement mixin.
#
# MIGRATION NOTE: in v2 the marker file was a setup.files create-time write and
# the markers were environment.variables. Neither needs anything from create
# time (markerId resolves at build), so both become overlay content here: the
# marker file is baked under /home/agent and the two env vars are set as ENV on
# the final stage, which merges into the composed image. This removes the
# install-phase footprint entirely - the kit reaches no network and holds no
# secret.
#
# The overlay lands on any base agent workload. The user (and the agent) never
# need to run anything from it; the markers are passive attestation.

ARG MARKER_ID=sandbox-wrapped

# Build stage: write the marker file with the resolved markerId, then normalize
# ownership. The marker is mode 0444 (read-only) like the v2 file. Nothing from
# this stage ships except /out.
FROM debian:bookworm-slim AS build
ARG MARKER_ID
RUN set -eu; \
    mkdir -p /out/home/agent; \
    printf 'marker=%s\nenforced=1\n' "$MARKER_ID" > /out/home/agent/.sandbox-enforced; \
    chmod 0444 /out/home/agent/.sandbox-enforced; \
    # Overlay ownership invariants: /home owned by root (0:0), /home/agent and
    # everything under it owned by the agent user (uid 1000). chown /home first,
    # then the agent subtree, so the file lands at 1000:1000.
    chown -R 0:0 /out/home; \
    chown -R 1000:1000 /out/home/agent

# The overlay: a scratch root carrying the marker file plus the env markers.
FROM scratch
ARG MARKER_ID
COPY --from=build /out /
# Host-side endpoint policy allow-lists agent processes carrying this marker;
# any agent process that spawns without it is denied at the endpoint. ENV on the
# final stage merges into the composed image, so it reaches the agent.
ENV SANDBOX_ENFORCED=1 \
    SANDBOX_ENFORCEMENT_MARKER=${MARKER_ID}
