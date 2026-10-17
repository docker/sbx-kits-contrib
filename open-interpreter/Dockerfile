# syntax=docker/dockerfile:1.7
# Base image for the `open-interpreter` sandbox kit.
#
# Open Interpreter is pre-baked so sandbox creation is fast and so its
# install-time fetches (a C compiler for psutil, uv's Python 3.12 standalone
# download, PyPI resolution) never have to sit in this kit's *runtime*
# network allowlist -- the engine enforces one allowlist per sandbox and
# cannot distinguish a build-time fetch from one the running agent might
# make.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# pi/openclaw/kiro/copilot/hermes-agent/aider.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant and no start-docker label: Open Interpreter's own code
# never shells out to `docker` and declares no dependency on it (checked
# against its PyPI requires_dist and its sdist source -- the only "docker"
# hit anywhere in the package is a comment in computer_use/loop.py describing
# *upstream's own* reference container, never something this package
# launches). OI executes the code it writes directly in this container via
# in-process Jupyter kernels; it has no feature that launches a second
# container.

# Open Interpreter's release cadence does not justify rolling-install
# machinery: PyPI shows no release after 0.4.3 (2024-10-24) as of this
# writing -- check `pip index versions open-interpreter` before assuming
# that's still true. An explicit pin costs nothing when there is no upstream
# drift to chase, and if a new release does appear, bumping this ARG is the
# same amount of work a cache-busting ADD would have been.
ARG OPEN_INTERPRETER_VERSION=0.4.3

USER root
# open-interpreter's psutil dependency has no prebuilt wheel for the Python
# 3.12 standalone runtime uv installs below on some architectures (confirmed
# on arm64) and falls back to compiling from source, which needs a C
# compiler this base image doesn't ship by default. Build-time only: nothing
# at runtime recompiles a package.
RUN apt-get update -qq && apt-get install -y -qq gcc python3-dev && rm -rf /var/lib/apt/lists/*

USER agent
WORKDIR /home/agent

RUN <<'EOF'
set -eu

# --python 3.12: the base image ships Python 3.13, but open-interpreter's
# numpy dependency has no Python 3.13 wheel. uv downloads a standalone
# Python 3.12 runtime automatically. --with "setuptools<81": open-interpreter
# still imports pkg_resources at startup, which setuptools>=81 dropped
# entirely (confirmed by hand: ModuleNotFoundError at runtime, not install
# time); setuptools<81 still bundles it, with just a deprecation warning.
uv tool install --with "setuptools<81" --python 3.12 "open-interpreter==${OPEN_INTERPRETER_VERSION}"

# open-interpreter's own dependency range is litellm<2.0.0,>=1.41.26 -- a
# range, not an exact pin -- so a fresh install resolves whatever is newest
# under that ceiling. Anthropic subscription (OAuth) login needs
# optionally_handle_anthropic_oauth() in litellm/llms/anthropic/common_utils.py
# to recognize an OAuth-shaped api_key directly, which is only true from
# litellm 1.81.12 onward. Confirmed by installing exactly this pin: it
# resolves litellm 1.83.0, past that floor, so no override is needed here.
# The assertion below still proves it rather than assuming the range keeps
# resolving something fixed: a future open-interpreter release narrowing
# that ceiling downward is what would make this gate start failing.
TOOL_PY="$HOME/.local/share/uv/tools/open-interpreter/bin/python3.12"
[ -x "$TOOL_PY" ]

"$TOOL_PY" -c "
from litellm.llms.anthropic.common_utils import optionally_handle_anthropic_oauth as f
h, _ = f({}, 'sk-ant-oat01-proxy-managed')
assert 'x-api-key' not in h, h
assert h.get('authorization') == 'Bearer sk-ant-oat01-proxy-managed', h
assert 'anthropic-beta' in h, h
"

"$HOME/.local/bin/interpreter" --version
EOF

# Both variables are litellm's own official switches (litellm/__init__.py,
# litellm/anthropic_beta_headers_manager.py) for a config it otherwise
# fetches at runtime from raw.githubusercontent.com/BerriAI/litellm/main/...:
# the model cost/context-window map and the Anthropic beta-header mapping.
# Each already falls back to its own bundled copy on a failed fetch, so
# setting these doesn't change behavior on a failure -- it removes the fetch
# attempt itself. Unlike aider, open-interpreter's own allowlist keeps
# api.github.com/raw.githubusercontent.com off the list already (nothing in
# its source fetches from either at runtime -- see spec.yaml), so this is
# what makes that omission complete rather than partial.
ENV LITELLM_LOCAL_MODEL_COST_MAP=True
ENV LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True

# COPY, not a reference to the kit's files/ tree: this is what makes the
# image's own CMD work when the image is run directly (docker run, or before
# the kit's setup.startup hook has ever executed), independent of sbx. The
# kit's sandbox.entrypoint in spec.yaml points at the files/home/ copy of
# this same script instead, so a fix to it reaches an existing sandbox on
# its next create without waiting on an image republish.
COPY --chmod=0755 files/home/.local/bin/open-interpreter-start.sh /usr/local/bin/open-interpreter-start

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "open-interpreter".
LABEL com.docker.sandboxes.flavor="open-interpreter"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/open-interpreter-start"]
