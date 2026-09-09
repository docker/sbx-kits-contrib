# syntax=docker/dockerfile:1.7
# Base image for the `nanobot` sandbox kit. PyPI stays reachable at
# runtime regardless of this bake: nanobot's own `cli_apps` tool
# pip-installs further packages at the agent's own request, enabled by default.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# No -docker variant and no start-docker label: nanobot-ai's dependency tree
# (checked against upstream's pyproject.toml) has no Docker dependency, and
# neither the kit's config nor its entrypoint touches a container engine.

# BuildKit re-fetches this URL on every build to compute its digest, so
# this layer is a cache hit until PyPI ships a new nanobot-ai release, and
# re-runs -- picking up the new version -- exactly when it has.
ADD --chmod=644 https://pypi.org/pypi/nanobot-ai/json /tmp/nanobot-release.json

USER agent
WORKDIR /home/agent

# `uv tool install`, not `pip install --break-system-packages`: the
# template's Python is externally managed (PEP 668); uv builds its own
# isolated venv instead of touching system site-packages.
#
# The version is read out of the JSON ADDed above, not re-resolved at RUN
# time, so it's a pure function of that layer -- pinning both arches to the
# same release. `nanobot --version` is the build-time gate: a broken
# release fails the build.
#
# /tmp/nanobot-release.json is left in place: it's root-owned from the ADD
# (this RUN runs as agent, so it couldn't unlink it anyway).
RUN set -eu; \
    version="$(python3 -c 'import json; print(json.load(open("/tmp/nanobot-release.json"))["info"]["version"])')"; \
    uv tool install "nanobot-ai==${version}"; \
    nanobot --version

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "nanobot".
LABEL com.docker.sandboxes.flavor="nanobot"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
# No --config flag: the kit's config at /home/agent/.nanobot/config.json is
# files/ content, not baked into this image, so a path here would fail
# `Config file not found` on a bare `docker run`. sandbox.entrypoint in
# spec.yaml passes it once files/ has landed.
CMD ["nanobot", "agent"]
