# syntax=docker/dockerfile:1
# The v2 install hook was pure pinned content, so v3 bakes it into a portable
# overlay instead of downloading it on every sandbox create.
FROM docker/sandbox-templates:shell AS build

USER agent
WORKDIR /home/agent
# A managed interpreter is load-bearing for an overlay: it keeps the copied
# virtualenv independent of whichever Python version the composed base carries.
RUN set -eu; \
    uv tool install --managed-python --python 3.12 "cloudsmith-cli==1.26.0"; \
    cloudsmith --version

USER root
RUN set -eu; \
    mkdir -p /out/home/agent/.local/share /out/home/agent/.local/bin /out/usr/local/bin; \
    cp -a /home/agent/.local/share/uv /out/home/agent/.local/share/uv; \
    cp -a /home/agent/.local/bin/cloudsmith /out/home/agent/.local/bin/cloudsmith; \
    ln -s /home/agent/.local/bin/cloudsmith /out/usr/local/bin/cloudsmith; \
    chown -R 1000:1000 /out/home/agent

# The overlay lands on any workload. Additive ENV from a mixin is merged into
# the composed image, preserving v2's explicit proxy sentinel.
FROM scratch
COPY --from=build /out /
ENV CLOUDSMITH_API_KEY=proxy-managed
