# syntax=docker/dockerfile:1
# Content for the `opencode-model-runner` workload kit.
#
# The v2 kit shipped no Dockerfile: it named this published template in
# `sandbox.image` and declared the entrypoint beside it. This image reference
# is that value carried over verbatim. A v3 workload's layers are the root
# filesystem, so the recipe says the same thing the v2 pair did, in the slot
# the image config already owns.
#
# Nothing is installed on top: this kit's whole substance is the provider
# config its lifecycle `files:` entry writes, which is a declaration rather
# than content, and OpenCode fetches the discovery plugin itself at startup.
FROM docker/sandbox-templates:opencode-docker

# v2's sandbox.entrypoint. There was no `environment.variables` block to carry.
ENTRYPOINT ["opencode"]
