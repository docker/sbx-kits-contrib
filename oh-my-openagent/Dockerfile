# syntax=docker/dockerfile:1

# Base image for the `oh-my-openagent` sandbox kit.
#
# Built from the prebuilt oh-my-openagent agent image published by the OmO
# project at ghcr.io. The sandbox boots zsh as the agent entrypoint.
#
# Requires egress to api.anthropic.com and registry.npmjs.org (the agent
# fetches extensions, skills, and prompt templates from npm on startup).
# Runtime egress to platform.claude.com is declared in spec.yaml's network
# policy for OAuth token refresh.

ARG BASE_IMAGE=ghcr.io/yokharian/oh-my-openagent-sbx-kit:latest
FROM ${BASE_IMAGE}

# Re-declared after FROM: a build arg defined before FROM is only visible to
# FROM lines without this.
ARG BASE_IMAGE

USER agent

# Read by sbx as an agent identifier: surfaced as the image's Agent in the
# API, and used to warn when a template looks built for a different agent than
# the one being run. Must be the kit's own name, not the base's.
LABEL com.docker.sandboxes.flavor="oh-my-openagent"

# Informational; nothing in sbx reads it. Records what this image was built
# on, since the base is a floating tag rebuilt nightly.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

CMD ["zsh"]
