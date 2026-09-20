# syntax=docker/dockerfile:1
# The content of the `aider` workload kit -- the v2 Dockerfile that built
# docker.io/sbx/aider-image:latest, now the kit's own recipe. A v3 workload's
# layers are the root filesystem, so there is no separate published base image
# and no sandbox.image pointing at one.
#
# Aider is baked in rather than installed at sandbox-create time, which is what
# keeps its install-time fetches (uv's Python 3.12 standalone download, PyPI
# resolution for aider-chat) out of the kit's network policy entirely: a build
# runs before any phase the policy scopes, so neither the install nor the
# runtime allow list has to admit PyPI.
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

# Supplied by the descriptor's `version` arg; declared bare here so the pin
# lives in exactly one place (aider.yaml) rather than in two that can drift.
ARG AIDER_VERSION

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
# makes leaving raw.githubusercontent.com out of the runtime allow list a
# closed decision instead of "probably fine because it'll fail soft".
ENV LITELLM_LOCAL_MODEL_COST_MAP=True
ENV LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True

# v2's environment.variables, in the slot OCI already owns for static env.
ENV AIDER_ANALYTICS=false \
    AIDER_AUTO_COMMITS=true \
    AIDER_CHECK_UPDATE=false \
    AIDER_MODEL=sonnet

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
# MIGRATION NOTE: v2's Dockerfile ended at `WORKDIR /home/agent`, which was
# only ever the `docker run` working directory -- the v2 engine mounted the
# workspace wherever it chose and told the agent through $WORKDIR. Under
# sbx@1 the image's working directory *is* where the host places the
# workspace, so it moves to the conventional sibling of $HOME. Leaving it at
# /home/agent would mount the user's checkout over the home directory the
# lifecycle file entry writes .aider.conf.yml into.
WORKDIR /home/agent/workspace
# v2's sandbox.entrypoint. v2's `CMD ["aider"]` was dead for sandbox launch --
# the spec's entrypoint won -- and in v3 the image config is the contract, so
# it is stated as the ENTRYPOINT it always effectively was.
ENTRYPOINT ["aider"]
