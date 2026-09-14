# syntax=docker/dockerfile:1.7
# Base image for the `aider` sandbox kit.
#
# Aider is pre-baked so sandbox creation is fast and so its install-time
# fetches (uv's Python 3.12 standalone download, PyPI resolution for
# aider-chat) never have to sit in this kit's *runtime* network allowlist --
# the engine enforces one allowlist per sandbox and cannot distinguish a
# build-time fetch from one the running agent might make.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# pi/openclaw/kiro/copilot/hermes-agent.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant and no start-docker label: Aider's own code never
# shells out to `docker` and aider-chat declares no dependency on it (checked
# against its PyPI requires_dist and its sdist source -- the only "docker"
# hits in the sdist are upstream's own Docker *distribution* of Aider and a
# benchmark harness, neither reachable from this kit's entrypoint). Aider
# edits files and runs the project's own test/build commands directly in
# this container; it has no feature that launches a second container.

USER agent
WORKDIR /home/agent

# Pinned rather than floating: aider-chat's own release cadence is sparse
# and irregular on PyPI (six months elapsed between 0.86.1 and 0.86.2, after
# a tighter run of releases before that), unlike the weekly-or-better
# cadence that justifies a rolling `latest` elsewhere in this repo (crush,
# junie). Bumping AIDER_VERSION is a deliberate, tested step.
ARG AIDER_VERSION=0.86.2

RUN <<'EOF'
set -eu

uv tool install --python 3.12 "aider-chat==${AIDER_VERSION}"

"$HOME/.local/bin/aider" --version
EOF

# Both variables are litellm's own official switches (litellm/__init__.py,
# litellm/anthropic_beta_headers_manager.py) for a config it otherwise
# fetches at runtime from raw.githubusercontent.com/BerriAI/litellm/main/...:
# the model cost/context-window map and the Anthropic beta-header mapping.
# Each already falls back to its own bundled copy on a failed fetch (a
# blocked host would just log a warning), so setting these doesn't change
# behavior on a failure -- it removes the fetch attempt itself, which is what
# makes dropping raw.githubusercontent.com from the runtime allowlist a
# closed decision instead of "probably fine because it'll fail soft".
ENV LITELLM_LOCAL_MODEL_COST_MAP=True
ENV LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "aider".
LABEL com.docker.sandboxes.flavor="aider"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["aider"]
