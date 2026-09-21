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

# The pin, handed in by the frontend from the descriptor's `version` arg
# (buildArg: NANOBOT_VERSION). The default is repeated here so a plain
# `docker build` of this file still works; nanobot.yaml is the authority and
# carries the PyPI query that establishes the value.
ARG NANOBOT_VERSION=0.3.5

USER agent
WORKDIR /home/agent

# `uv tool install`, not `pip install --break-system-packages`: the
# template's Python is externally managed (PEP 668); uv builds its own
# isolated venv instead of touching system site-packages.
#
# This used to `ADD https://pypi.org/pypi/nanobot-ai/json` and read
# `info.version` out of it at RUN time, so every build installed whatever PyPI
# currently called newest -- both arches got the same release, but which
# release was whatever the day decided, and the descriptor had no honest
# version to publish. The `==${NANOBOT_VERSION}` selector replaces that: uv
# fails outright when PyPI cannot serve the pinned release rather than sliding
# to a neighbour, and the ADD is gone with the floating read it fed.
#
# The second RUN is the build-time gate and the check that keeps the descriptor
# honest: it runs the installed entry point, so a broken release fails the
# build, and it compares what nanobot reports against the pin, so a package
# whose contents disagree with its PyPI version fails here rather than
# publishing `nanobot@${NANOBOT_VERSION}` over content that is not that
# release.
RUN set -eu; \
    uv tool install "nanobot-ai==${NANOBOT_VERSION}"
RUN set -eu; \
    reported="$(nanobot --version)"; \
    echo "nanobot --version: ${reported}"; \
    case "${reported}" in \
      *"${NANOBOT_VERSION}"*) ;; \
      *) echo "pin mismatch: descriptor says ${NANOBOT_VERSION}, nanobot reports '${reported}'" >&2; exit 1 ;; \
    esac

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
