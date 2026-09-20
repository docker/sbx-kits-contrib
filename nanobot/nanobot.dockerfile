# syntax=docker/dockerfile:1.7
# Content for the `nanobot` workload kit. PyPI stays reachable at
# runtime regardless of this bake: nanobot's own `cli_apps` tool
# pip-installs further packages at the agent's own request, enabled by default.
#
# MIGRATION NOTE: this was v2's Dockerfile, built by CI into
# docker.io/sbx/nanobot-image:latest and named back from spec.yaml's
# `sandbox.image`. In v3 the recipe is the kit's content directly, so the
# published-tag round trip is gone. The base is v2's default, verbatim.
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

# MIGRATION NOTE: v2 shipped this config as kit content under `files/home/`,
# which the v2 artifact loader staged into the sandbox at create -- which is
# why the Dockerfile deliberately did NOT bake it and the image's CMD carried
# no --config flag. In v3 the kit and the image are one artifact, so "kit
# content that is not image content" has no meaning: the file is copied in
# here, at the same in-image path, and the entrypoint below names it the way
# v2's `sandbox.entrypoint` did.
COPY --chown=agent:agent files/home/.nanobot/config.json /home/agent/.nanobot/config.json

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "nanobot".
LABEL com.docker.sandboxes.flavor="nanobot"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
ENV NANOBOT_AGENTS__DEFAULTS__WORKSPACE=/home/agent/nanobot

USER agent
WORKDIR /home/agent
# v2's sandbox.entrypoint. MIGRATION NOTE: v2's `CMD ["nanobot", "agent"]` is
# dropped rather than kept beside it -- the launch argv is Entrypoint + Cmd
# (SPEC-v3 §8), so leaving the CMD in place would append a second
# `nanobot agent` to every launch.
ENTRYPOINT ["nanobot", "agent", "--config", "/home/agent/.nanobot/config.json"]
