# syntax=docker/dockerfile:1
# This mixin's content is the runbook tree. The requests dependency remains a
# lifecycle install so it targets the composed base's own Python interpreter.
FROM docker/sandbox-templates:shell AS build
USER root
RUN mkdir -p /out/home/agent
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# NO_PROXY is appended at shell start rather than set in the image config: the
# composer refuses two kits that set one variable to different values, and the
# base already sets NO_PROXY.
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' \
      'export NO_PROXY="${NO_PROXY:+$NO_PROXY,}host.docker.internal"' \
      'export no_proxy="$NO_PROXY"' \
      > /out/etc/profile.d/dynatrace-env.sh

# Copying from /out preserves root ownership on /home and agent ownership from
# /home/agent downward when the overlay lands on an unknown workload.
FROM scratch
COPY --from=build /out /
