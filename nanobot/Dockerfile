# syntax=docker/dockerfile:1.7
# Base image for the `nanobot` sandbox kit.
#
# nanobot is a single pip package, so this pre-bake buys only one thing: the
# kit's own bootstrap install moves to build time, off this kit's *runtime*
# network allowlist -- the engine enforces one allowlist per sandbox and
# cannot distinguish a build-time fetch from one the running agent might
# make. PyPI itself stays reachable at runtime regardless: nanobot's own
# `cli_apps` tool pip-installs further packages at the agent's own request,
# enabled by default, and nothing here turns that off.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# hermes-agent/pi/openclaw/kiro/copilot.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# No -docker variant and no start-docker label: nanobot-ai's dependency tree
# (checked against upstream's pyproject.toml) has no Docker dependency, and
# neither the kit's config nor its entrypoint touches a container engine.

# Rolling updates by design: nanobot-ai ships onto PyPI roughly monthly, not
# daily, so tracking its latest release (rather than a hand-maintained pin)
# is the same call this repo already makes for pi and Hermes. The ADD below
# is what makes that work under CI's layer cache: BuildKit re-fetches the URL
# on every build to compute its digest, so this layer is a cache hit when the
# published version hasn't changed and re-runs -- picking up the new
# version -- exactly when it has.
ADD --chmod=644 https://pypi.org/pypi/nanobot-ai/json /tmp/nanobot-release.json

USER agent
WORKDIR /home/agent

# uv tool install, not `pip install --break-system-packages`: the template's
# Python is externally managed (PEP 668), and `--break-system-packages` was
# only ever working around that by installing straight into the managed
# system site-packages. `uv tool install` instead builds nanobot-ai its own
# isolated venv and symlinks the `nanobot` entry point into
# ~/.local/bin -- already on PATH in this template -- so the install can
# neither be broken by nor break anything else on the system Python.
#
# The version installed is read out of the JSON ADDed above rather than
# re-resolved at RUN time, so what lands in the image is a pure function of
# that layer's content -- within one build that pins both architectures to
# the same release. `nanobot --version` is the build-time gate: it actually
# imports and runs the installed code, so a release this install cannot
# complete, or whose entry point throws, fails the build -- and so the
# nightly publish -- instead of shipping a non-starting agent.
#
# /tmp/nanobot-release.json is deliberately not removed: it is root-owned
# from the ADD (this RUN executes as agent, so it couldn't unlink it
# anyway) and lives in the ADD's own layer, so deleting it here would only
# add a whiteout on top of the few hundred bytes it already costs.
RUN set -eu; \
    version="$(python3 -c 'import json; print(json.load(open("/tmp/nanobot-release.json"))["info"]["version"])')"; \
    uv tool install "nanobot-ai==${version}"; \
    nanobot --version

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "nanobot".
LABEL com.docker.sandboxes.flavor="nanobot"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
# No --config flag here: the config the kit ships at
# /home/agent/.nanobot/config.json is kit content (files/), not baked into
# this image, so an explicit path to it would fail `Config file not found`
# on a bare `docker run`. sandbox.entrypoint in spec.yaml passes it
# explicitly instead, once the kit's files/ tree has actually landed.
CMD ["nanobot", "agent"]
