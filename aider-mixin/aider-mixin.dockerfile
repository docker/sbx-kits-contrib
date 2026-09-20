# syntax=docker/dockerfile:1
# The overlay: aider-chat landing on any base.
#
# `uv tool install` is one of the installs that genuinely cannot be relocated,
# so this does not try. It has no --prefix, and what it produces is a venv full
# of absolute-path shebangs plus a standalone CPython 3.12 it downloads into
# ~/.local/share/uv/python -- both of which stop working the moment the tree
# moves. So the shape is: take the workload's own base as a build stage, run
# the *unmodified* install there, and copy the specific paths it produced into
# a scratch overlay at exactly the paths they were built for.
#
# The copy is the whole of /home/agent/.local rather than just .local/bin: the
# bin entries are thin shims into .local/share/uv/tools/aider-chat and the
# interpreter under .local/share/uv/python, so copying the shims alone would
# land an overlay of dangling launchers.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

# Supplied by the descriptor's `version` arg; declared bare so the pin lives in
# exactly one place (aider-mixin.yaml).
ARG AIDER_VERSION

USER agent
WORKDIR /home/agent

RUN <<'EOF'
set -eu

uv tool install --python 3.12 "aider-chat==${AIDER_VERSION}"

"$HOME/.local/bin/aider" --version
EOF

# v2's environment.variables, plus the two litellm switches the v2 Dockerfile
# set as image ENV. A mixin's image config is not the composed image's, so
# static env rides the overlay as a profile script instead.
#
# LITELLM_LOCAL_MODEL_COST_MAP and LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS are
# litellm's own official switches for a config it otherwise fetches at runtime
# from raw.githubusercontent.com. Setting them removes the fetch attempt
# itself, which is what keeps that host out of the kit's runtime allow list.
USER root
RUN mkdir -p /out/etc/profile.d && \
    printf 'export LITELLM_LOCAL_MODEL_COST_MAP=True\nexport LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True\nexport AIDER_ANALYTICS=false\nexport AIDER_AUTO_COMMITS=true\nexport AIDER_CHECK_UPDATE=false\nexport AIDER_MODEL=sonnet\n' \
      > /out/etc/profile.d/aider-env.sh

# The install tree is staged into /out rather than copied into the overlay with
# `COPY --chown`: BuildKit applies that flag to every parent it creates, so
# copying to /home/agent/.local would ship /home itself owned by the agent, and
# an overlay's directory entries override the base's. Numeric ownership because
# scratch carries no /etc/passwd for a name to resolve against; 1000:1000 is
# the platform floor's `agent` user. /out/home stays root's.
RUN mkdir -p /out/home/agent \
 && cp -a /home/agent/.local /out/home/agent/.local \
 && chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=build /out /
