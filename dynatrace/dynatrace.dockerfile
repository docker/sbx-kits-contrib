# syntax=docker/dockerfile:1
# This mixin's content is the runbook tree. The requests dependency remains a
# lifecycle install so it targets the composed base's own Python interpreter.
FROM docker/sandbox-templates:shell AS build
USER root
RUN mkdir -p /out/home/agent
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# Copying from /out preserves root ownership on /home and agent ownership from
# /home/agent downward when the overlay lands on an unknown workload.
FROM scratch
COPY --from=build /out /

# Additive mixin environment is merged into the composed workload.
ENV NO_PROXY=localhost,127.0.0.1,host.docker.internal
ENV no_proxy=localhost,127.0.0.1,host.docker.internal
