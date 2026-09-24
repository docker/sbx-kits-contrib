# syntax=docker/dockerfile:1
# Only the static parser config becomes overlay content. The two files carrying
# create-phase kit args are authored once in lifecycle@1.files; copying their
# v2 templates here as well would create stale, unexpanded fallback copies.
#
# A build stage creates the /home hierarchy with explicit ownership. Overlay
# directory entries replace those from the workload: /home must remain root
# owned while /home/agent and its content belong to uid/gid 1000.
FROM docker/sandbox-templates:shell-docker AS build

COPY files/home/.config/fluent-bit/parsers.conf \
     /out/home/agent/.config/fluent-bit/parsers.conf

USER root
RUN set -eux; \
    chown 0:0 /out /out/home; \
    chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=build /out /
