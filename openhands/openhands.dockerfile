# syntax=docker/dockerfile:1.7
# The openhands workload's content. This is the v2 kit's Dockerfile: v2
# published it as docker.io/sbx/openhands-image:latest and pointed
# `sandbox.image` at the result, while a v3 workload's layers *are* the
# root filesystem -- so the intermediate publish disappears and this recipe
# builds the kit directly. v2's environment.variables and sandbox.entrypoint
# land at the bottom, in the image config that already owns runtime config.
#
# Baking the install also drops the foreground `uv tool upgrade` the kit used
# to run on every start -- there is nothing to upgrade to in a fixed image,
# and it blocked the entrypoint.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant: SANDBOX_TYPE=local, and the CLI's workspace setup
# (openhands_cli/setup.py) builds `Workspace(...)` with no `host` arg, so
# the SDK factory (openhands/sdk/workspace/workspace.py) always resolves to
# `LocalWorkspace`, never `DockerWorkspace`. Re-check both files if
# upstream restructures workspace selection.

USER agent
WORKDIR /home/agent

# PyPI's JSON API has no literal "latest" segment -- omitting the version
# entirely returns the newest release, which is why OPENHANDS_VERSION
# defaults to empty. BuildKit re-fetches the URL on every build to compute
# its digest, so this layer re-runs exactly when the resolved release
# changes.
ARG OPENHANDS_VERSION=
ADD --chmod=644 https://pypi.org/pypi/openhands/${OPENHANDS_VERSION:+${OPENHANDS_VERSION}/}json /tmp/openhands-release.json

# `openhands` (the V1 terminal CLI, distinct from `openhands-ai` and
# `openhands-sdk`) pins requires-python to 3.12.x, so `--python 3.12` makes
# uv download a standalone CPython 3.12 the first time this layer builds.
#
# `openhands --version` is the build-time gate: a broken release fails the
# build instead of shipping a non-starting agent.
#
# /tmp/openhands-release.json is left in place: it lands root-owned
# regardless of USER, this RUN runs as agent, and it's already in the
# ADD's own layer -- an agent `rm` would fail on it anyway.
RUN set -eu; \
    version="$(grep -oP '"version":\s*"\K[^"]+' /tmp/openhands-release.json)"; \
    [ -n "$version" ]; \
    uv tool install --python 3.12 "openhands==${version}"; \
    "$HOME/.local/bin/openhands" --version

# The kit's files/home/ tree. v2's artifact loader copied it into /home/agent/
# at sandbox create; v3 has no implicit files/ convention, so the recipe lands
# it. --chmod=0644 reproduces the mode the loader left, which is why the
# ENTRYPOINT below invokes the script through `sh` rather than exec'ing it --
# keeping v2's sandbox.entrypoint spelling exactly.
COPY --chown=agent:agent --chmod=0644 \
     files/home/.local/bin/openhands-start.sh \
     files/home/.local/bin/openhands-anthropic-auth.sh \
     /home/agent/.local/bin/

# The 0755 copy the v2 image shipped so a plain `docker run` worked before
# the kit's files/ tree existed. It backed the v2 CMD; the ENTRYPOINT below
# is what launches the agent now, and this stays as the shell-callable name.
# openhands-anthropic-auth.sh is deliberately not copied alongside it: run
# standalone, its absence fails open (the script isn't `set -e`), so the
# entrypoint falls through to exec'ing openhands as-is.
COPY --chmod=0755 files/home/.local/bin/openhands-start.sh /usr/local/bin/openhands-start

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "openhands".
LABEL com.docker.sandboxes.flavor="openhands"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
#
# Not LLM_MODEL: openhands-anthropic-auth.sh is the sole source of that
# variable now, and it deliberately leaves it unset when there's no
# Anthropic credential to resolve or a persisted agent_settings.json
# already exists -- a static default here would apply regardless and
# silently override either of those states.
ENV OPENHANDS_SUPPRESS_BANNER=1 \
    SANDBOX_TYPE=local

USER agent
WORKDIR /home/agent
# v2's sandbox.entrypoint. Kit content, not the installed binary: the
# entrypoint has to source the Anthropic auth env file the startup hook
# writes. Setting ENTRYPOINT also clears the CMD inherited from the base, so
# nothing is appended to it.
ENTRYPOINT ["sh", "/home/agent/.local/bin/openhands-start.sh", "--always-approve"]
