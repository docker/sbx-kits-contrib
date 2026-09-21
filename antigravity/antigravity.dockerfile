# syntax=docker/dockerfile:1
# The content of the `antigravity` workload kit -- the v2 Dockerfile that built
# docker.io/sbx/antigravity-image:latest, now the kit's own recipe. A v3
# workload's layers are the root filesystem, so there is no separate published
# base image and no sandbox.image pointing at one.
#
# agy is baked in rather than installed at sandbox-create time, which keeps the
# install.sh fetch out of the kit's network policy entirely: a build runs
# before any phase the policy scopes.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Runs as the base image's default user (`agent`, uid 1000), which matters:
# install.sh is a per-user installer, so --dir has to name a directory the user
# that will run the agent owns. `agy --help` is the build-time gate -- it runs
# the installed binary, so an install that lands nothing executable fails the
# build instead of shipping a non-starting agent.
#
# No version arg reaches this line, and that is not an oversight: install.sh
# parses only `-d|--dir` and `-h|--help` and resolves what to install from a
# manifest it fetches itself. That is why the descriptor's provide is
# unversioned -- see antigravity.yaml for the full argument and for what
# upstream would have to change to make a pin possible.
USER agent
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-antigravity.sh && \
    bash /tmp/install-antigravity.sh --dir /home/agent/.local/bin && \
    rm -f /tmp/install-antigravity.sh && \
    agy --help >/dev/null

# v2's environment.variables, in the slot OCI already owns for static env.
# agy shells out to the browser opener for its Google sign-in; xdg-open is
# what the template ships.
ENV BROWSER=xdg-open

# A request to the runtime, not a description of the image: the base carries a
# Docker engine, and this asks for it to be started. Stays a label -- it is not
# a v3 capability.
LABEL com.docker.sandboxes.start-docker="true"

# OVERRIDES the value inherited from the base image, which describes the base
# rather than this image. Not optional: sbx reads `flavor` as the image's agent
# identifier, and left inherited it would report "shell-docker".
LABEL com.docker.sandboxes.flavor="antigravity"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# MIGRATION NOTE: v2's Dockerfile ended at `WORKDIR /home/agent`, which was
# only ever the `docker run` working directory -- the v2 engine mounted the
# workspace wherever it chose. Under sbx@1 the image's working directory *is*
# where the host places the workspace, so it moves to the conventional sibling
# of $HOME; leaving it at /home/agent would mount the user's checkout over the
# home directory holding ~/.gemini and ~/.local/bin/agy.
WORKDIR /home/agent/workspace

# MIGRATION NOTE: v2 split the launch across two fields the engine recombined
# -- `sandbox.entrypoint: [agy]` and `sandbox.command.default:
# [--dangerously-skip-permissions]` -- and the Dockerfile's own
# `CMD ["agy", "--dangerously-skip-permissions"]` was dead for sandbox launch,
# since the spec's values won. In v3 the image config is the contract, and
# ENTRYPOINT + CMD are the slots those two fields map onto one for one, so the
# effective argv is unchanged.
ENTRYPOINT ["agy"]
CMD ["--dangerously-skip-permissions"]
