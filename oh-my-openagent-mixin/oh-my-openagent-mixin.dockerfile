# syntax=docker/dockerfile:1.7
# The OmO CLI as an overlay.
#
# The build stage runs the vendor installer unmodified on the base it targets,
# then copies the resulting `omo` binary into a scratch overlay. That is the
# shape this repo prescribes for an install whose bin path cannot be relocated
# afterwards: the binary lands at the absolute path it was built at, so a shim
# on /usr/local/bin resolves on any base.
#
# WHAT THIS OVERLAY CANNOT CARRY: the agent and its credential. It adds `omo`
# to whatever agent the base workload already runs; the Anthropic binding stays
# owned by that workload.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER agent

RUN curl -fsSL https://get.omo.dev/install.sh -o /tmp/omo-install.sh \
    && OMO_NO_MODIFY_PATH=1 bash /tmp/omo-install.sh \
    && rm -f /tmp/omo-install.sh \
    && "$HOME/.local/bin/omo" --help > /dev/null

USER root

# Ownership is mirrored from the build stage with `chown --reference`: an
# overlay's directory entries carry their own ownership onto the composed image,
# so a root-owned /home/agent/.local/bin would shadow the base's agent-owned
# path and break installs that write there.
RUN set -eu; \
    mkdir -p /out/home/agent/.local/bin /out/usr/local/bin /out/home /out/home/agent; \
    cp -a /home/agent/.local/bin/. /out/home/agent/.local/bin/; \
    for d in /home /home/agent /home/agent/.local /home/agent/.local/bin; do \
      if [ -d "$d" ]; then chown --reference="$d" "/out${d}"; fi; \
    done; \
    ln -sf /home/agent/.local/bin/omo /out/usr/local/bin/omo

# No ENTRYPOINT: the base workload's launch command stays, and the user runs
# `omo` from the agent's shell.
FROM scratch
COPY --from=build /out /
