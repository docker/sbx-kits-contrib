# syntax=docker/dockerfile:1
# nanobot as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: `uv tool install` writes an isolated venv under
# ~/.local/share/uv/tools whose console scripts carry absolute interpreter
# paths, and uv has no prefix flag that would let the tree be built somewhere
# else and moved. So the shape the guide prescribes for exactly this case --
# run the unmodified install on the workload's base, then copy the specific
# resulting paths into a scratch overlay -- is what this does. The venv lands
# at the same absolute path it was built at, which is what keeps its shebangs
# resolving.
#
# The venv references the base template's own `python3`, because the install
# passes no `--python` and uv therefore adopts the interpreter it finds. That
# makes this overlay composable onto bases whose python3 is compatible with
# the template's -- which every sandbox-templates base is. There is no grammar
# to state a python floor: provides/requires name kit capabilities, and base
# workloads provide none for their interpreter.
FROM docker/sandbox-templates:shell AS build

# The same pin the workload makes, handed in by the frontend from the
# descriptor's `version` arg (buildArg: NANOBOT_VERSION); the default repeated
# here keeps a plain `docker build` of this file working. It replaces an
# `ADD https://pypi.org/pypi/nanobot-ai/json` whose `info.version` this RUN
# used to read, which installed whatever PyPI called newest on the day.
ARG NANOBOT_VERSION=0.3.5

USER agent
WORKDIR /home/agent
# --managed-python is load-bearing for an OVERLAY, in a way it is not for the
# workload beside it. A venv keeps its packages in lib/python3.<minor> and
# points bin/python at an absolute interpreter path; left to itself uv picks
# the build base's python3 (3.14 here), so the copied tree would resolve
# /usr/bin/python3 on the COMPOSED base and look for site-packages under that
# base's minor version. On anything but a 3.14 base the result is a launcher
# that runs and then fails with ModuleNotFoundError -- verified before this
# line existed, composed onto ubuntu:24.04 (python 3.12.3).
#
# Asking for a managed interpreter makes uv download a standalone CPython into
# ~/.local/share/uv, which the overlay already copies, so the venv points
# inside the tree it travels with and the overlay is self-contained. Pinned to
# 3.14 to match the interpreter the workload's own base runs.
RUN set -eu; \
    uv tool install --managed-python --python 3.14 "nanobot-ai==${NANOBOT_VERSION}"

# The build-time gate and the check that keeps the descriptor honest: it runs
# the installed entry point, so a broken release fails the build, and it
# compares what nanobot reports against the pin, so the overlay cannot carry
# content that disagrees with the version the descriptor publishes.
RUN set -eu; \
    reported="$(nanobot --version)"; \
    echo "nanobot --version: ${reported}"; \
    case "${reported}" in \
      *"${NANOBOT_VERSION}"*) ;; \
      *) echo "pin mismatch: descriptor says ${NANOBOT_VERSION}, nanobot reports '${reported}'" >&2; exit 1 ;; \
    esac

# The provider config the workload copies out of `files/home/`. It is inlined
# here rather than COPYed: a kit's build context is its own directory, so the
# overlay cannot reach the sibling workload's files/ tree. Kept byte-identical
# to nanobot/files/home/.nanobot/config.json -- the `${ANTHROPIC_API_KEY}`
# reference is expanded by nanobot itself at startup, not by the build.
COPY <<'EOF' /out/home/agent/.nanobot/config.json
{
  "agents": {
    "defaults": {
      "workspace": "/home/agent/nanobot",
      "model": "claude-sonnet-4-20250514",
      "max_iterations": 10,
      "max_tokens": 8192,
      "temperature": 0.1
    }
  },
  "providers": {
    "anthropic": {
      "api_key": "${ANTHROPIC_API_KEY}"
    }
  },
  "tools": {
    "exec": {
      "enabled": true,
      "timeout_seconds": 30,
      "restrictToWorkspace": true
    }
  }
}
EOF

USER root
# The specific paths the install produced, plus v2's environment.variables.
# A mixin's image config is not the composed image's, so the ENV the workload
# sets rides a profile.d snippet the base's login shell sources instead.
RUN mkdir -p /out/home/agent/.local/share /out/home/agent/.local/bin /out/etc/profile.d \
 && cp -a /home/agent/.local/share/uv /out/home/agent/.local/share/uv \
 && cp -a /home/agent/.local/bin/nanobot /out/home/agent/.local/bin/nanobot \
 && printf 'export NANOBOT_AGENTS__DEFAULTS__WORKSPACE=/home/agent/nanobot\nexport PATH="$HOME/.local/bin:$PATH"\n' \
      > /out/etc/profile.d/nanobot-env.sh \
 && chown -R 1000:1000 /out/home/agent

# The overlay: the tool venv, its launcher and the provider config, landing on
# any base.
FROM scratch
COPY --from=build /out /
