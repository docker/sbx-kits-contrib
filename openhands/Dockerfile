# syntax=docker/dockerfile:1.7
# Base image for the `openhands` sandbox kit.
#
# OpenHands is pre-baked so sandbox creation is fast and so `uv tool install`'s
# fetches (PyPI metadata and wheels, plus a standalone CPython -- see below)
# never have to sit in this kit's *runtime* network allowlist -- the engine
# enforces one allowlist per sandbox and cannot distinguish a build-time fetch
# from one the running agent might make. It also drops the foreground
# `uv tool upgrade` the kit used to run on every start: that step contradicts a
# fixed image (there is nothing to upgrade to that this image doesn't already
# have) and blocks the entrypoint until it finishes.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# hermes-agent/pi/openclaw/kiro/copilot.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant and no start-docker label: this kit sets
# SANDBOX_TYPE=local, and the CLI's own workspace setup (openhands_cli/
# setup.py) constructs `Workspace(working_dir=...)` with no `host` argument --
# the SDK's factory (openhands/sdk/workspace/workspace.py) resolves that
# unconditionally to `LocalWorkspace`, which runs commands via a plain
# subprocess (openhands/sdk/workspace/local.py) and never touches Docker.
# `DockerWorkspace` lives in the separate openhands-workspace package and is
# never imported by this path. So the terminal CLI this image runs never
# spawns a sandboxed runtime container, regardless of SANDBOX_TYPE -- re-check
# against those two files if upstream restructures workspace selection.

USER agent
WORKDIR /home/agent

# Rolling by design: the nightly scheduled run of build-and-publish-kits.yml
# rebuilds this image against whatever `openhands` is newest on PyPI. The ADD
# below is what makes that work under CI's layer cache: BuildKit re-fetches
# the URL on every build to compute its digest, so this layer is a cache hit
# when the resolved release has not changed and re-runs -- picking up the new
# version -- exactly when it has.
#
# Unlike npm's dist-tags or a GitHub releases API, PyPI's JSON API has no
# literal "latest" path segment (`/pypi/openhands/latest/json` 404s) --
# omitting the version segment entirely is what returns the newest release.
# OPENHANDS_VERSION therefore defaults to empty, and the `:+` substitution
# below inserts the version segment only when a caller pins one.
ARG OPENHANDS_VERSION=
ADD --chmod=644 https://pypi.org/pypi/openhands/${OPENHANDS_VERSION:+${OPENHANDS_VERSION}/}json /tmp/openhands-release.json

# `openhands` (the PyPI package for the V1 terminal CLI, distinct from the
# `openhands-ai`/legacy-monolith and `openhands-sdk` packages) pins
# requires-python to exactly 3.12.x, while the template ships 3.14 -- so
# `--python 3.12` makes uv download a standalone CPython 3.12 from a GitHub
# release (astral-sh/python-build-standalone) the first time this layer
# builds. That fetch, and the wheel downloads from PyPI, are what this bake
# moves off the runtime allowlist.
#
# `openhands --version` is the build-time gate: it actually imports and runs
# the installed code, so a release this installer cannot complete, or that
# imports something broken, fails the build -- and so the nightly publish --
# instead of shipping a non-starting agent.
#
# /tmp/openhands-release.json is deliberately not removed: a URL ADD always
# lands root-owned regardless of the active USER, this RUN executes as
# agent (uv tool install needs to, so its bin dir ends up agent-owned), and
# the file lives in the ADD's own layer anyway -- an agent-owned `rm` would
# fail on the root-owned file, and a root-owned one would only add a
# whiteout on top of the few KB the layer ships either way.
RUN set -eu; \
    version="$(grep -oP '"version":\s*"\K[^"]+' /tmp/openhands-release.json)"; \
    [ -n "$version" ]; \
    uv tool install --python 3.12 "openhands==${version}"; \
    "$HOME/.local/bin/openhands" --version

# COPY, not a reference to the kit's files/ tree: this is what makes the
# image's own CMD work when the image is run directly (docker run, or before
# the kit's setup.startup hook has ever executed), independent of sbx. The
# kit's sandbox.entrypoint in spec.yaml points at the files/home/ copy of
# this same script instead, so a fix to it reaches an existing sandbox on its
# next create without waiting on an image republish.
#
# openhands-anthropic-auth.sh is deliberately NOT copied alongside it: run
# standalone, openhands-start.sh's attempt to re-run that resolver fails
# open (the script isn't `set -e`, so a missing-file error on that line
# doesn't stop it) and the entrypoint falls through to exec'ing openhands
# with whatever the container environment already provides -- the same
# degrade-gracefully shape hermes-agent's copy of its own start script relies
# on.
COPY --chmod=0755 files/home/.local/bin/openhands-start.sh /usr/local/bin/openhands-start

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "openhands".
LABEL com.docker.sandboxes.flavor="openhands"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/openhands-start", "--always-approve"]
