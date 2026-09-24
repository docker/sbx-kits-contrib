# syntax=docker/dockerfile:1
# The v2 files/home tree becomes ordinary overlay content in v3. Installation
# still runs at create time because component choice, credentials, sandbox
# identity, and optional corporate certificates are create-time inputs.
#
# Explicit ownership preserves the workload's /home ownership while making the
# staged agent tree writable by the platform-floor uid/gid 1000.
FROM docker/sandbox-templates:shell-docker AS build

COPY files/home/ /out/home/agent/

USER root
RUN set -eux; \
    chmod 0755 /out/home/agent/.snyk-kit/*.sh; \
    chown 0:0 /out /out/home; \
    chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=build /out /

# Static image config is additive for a mixin and merges into the workload.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
