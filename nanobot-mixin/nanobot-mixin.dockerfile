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

# Same floating resolution as the workload: BuildKit re-fetches this URL every
# build to compute its digest, so the install layer is a cache hit until PyPI
# ships a new nanobot-ai release and re-runs exactly when it has.
ADD --chmod=644 https://pypi.org/pypi/nanobot-ai/json /tmp/nanobot-release.json

USER agent
WORKDIR /home/agent
RUN set -eu; \
    version="$(python3 -c 'import json; print(json.load(open("/tmp/nanobot-release.json"))["info"]["version"])')"; \
    uv tool install "nanobot-ai==${version}"; \
    nanobot --version

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
