# syntax=docker/dockerfile:1.7
# Open Interpreter as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: this kit installs through `uv tool install`, which writes an
# isolated venv under ~/.local/share/uv/tools whose console scripts and
# interpreter symlinks carry absolute paths, and it needs a C toolchain
# (gcc, python3-dev) on the way for psutil's source build on arm64. Neither
# half relocates -- uv has no prefix flag that would let the tree be built
# elsewhere and moved, and apt packages are not copyable content. So this
# takes the shape the guide prescribes for exactly that case: run the
# unmodified install on the workload's own base, then copy the specific
# resulting paths into a scratch overlay. The venv lands at the same absolute
# path it was built at, which is what keeps its shebangs resolving, and the
# toolchain stays behind in the build stage where it belongs (nothing at
# runtime recompiles a package).
#
# What crosses into the overlay is ~/.local/share/uv in full rather than just
# the tool directory: the install passes `--python 3.12` and uv answers that
# by downloading a standalone runtime under ~/.local/share/uv/python, which
# the tool venv then points at. Copying the tools tree alone would land a venv
# with no interpreter behind it. That standalone runtime is also what keeps
# this overlay from depending on the composed base's python version -- unlike
# the base template's own interpreter, it travels with the kit.
FROM docker/sandbox-templates:shell AS build

ARG OPEN_INTERPRETER_VERSION

USER root
# psutil has no prebuilt wheel for the Python 3.12 standalone runtime uv
# installs below on some architectures (confirmed on arm64) and falls back to
# compiling from source. Build-time only, and deliberately not copied out.
RUN apt-get update -qq && apt-get install -y -qq gcc python3-dev && rm -rf /var/lib/apt/lists/*

USER agent
WORKDIR /home/agent

# The workload's install, unmodified -- including its build-time gate, which
# is the thing that proves the overlay carries a working agent rather than a
# tree that merely unpacked.
RUN <<'EOF'
set -eu

# --python 3.12: the base image ships Python 3.13, but open-interpreter's
# numpy dependency has no Python 3.13 wheel. uv downloads a standalone
# Python 3.12 runtime automatically. --with "setuptools<81": open-interpreter
# still imports pkg_resources at startup, which setuptools>=81 dropped
# entirely; setuptools<81 still bundles it, with just a deprecation warning.
uv tool install --with "setuptools<81" --python 3.12 "open-interpreter==${OPEN_INTERPRETER_VERSION}"

# Anthropic subscription (OAuth) login needs
# optionally_handle_anthropic_oauth() in litellm/llms/anthropic/common_utils.py
# to recognize an OAuth-shaped api_key directly, which is only true from
# litellm 1.81.12 onward. open-interpreter's own range is a range, not a pin,
# so this asserts the resolved litellm rather than assuming it.
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

# The kit's own scripts and the seeded profile. This tree is a copy of
# ../open-interpreter/files/ and is kept byte-identical to it: a kit's build
# context is its own directory, so an overlay cannot reach the sibling
# workload's files/, and `diff -r` between the two is what catches drift.
# Copied without an exec bit, as the workload copies them, because both are
# invoked through `sh`.
COPY --chown=agent:agent files/home/ /out/home/agent/

USER root
# The specific paths the install produced, plus v2's environment.variables.
# A mixin's image config is not the composed image's, so the ENV the workload
# sets rides a profile.d snippet the base's login shell sources instead. The
# image-level launcher copy lands too, so `open-interpreter-start` works from
# the shell the way it does in the workload.
RUN mkdir -p /out/home/agent/.local/share /out/home/agent/.local/bin /out/usr/local/bin /out/etc/profile.d \
 && cp -a /home/agent/.local/share/uv /out/home/agent/.local/share/uv \
 && cp -a /home/agent/.local/bin/interpreter /out/home/agent/.local/bin/interpreter \
 && install -m 0755 /out/home/agent/.local/bin/open-interpreter-start.sh \
      /out/usr/local/bin/open-interpreter-start \
 && printf 'export LITELLM_LOCAL_MODEL_COST_MAP=True\nexport LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True\nexport PATH="$HOME/.local/bin:$PATH"\n' \
      > /out/etc/profile.d/open-interpreter-env.sh \
 && chown -R 1000:1000 /out/home/agent

# The overlay: the tool venv with its own Python, the kit's scripts and the
# launcher, landing on any base.
FROM scratch
COPY --from=build /out /
