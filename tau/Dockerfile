# syntax=docker/dockerfile:1.7
# Base image for the `tau` sandbox kit.
#
# tau is pre-baked for the usual reason -- sandbox creation only pulls a layer
# instead of resolving a Python environment -- and for a second one specific to
# this repo's e2e: a sandbox has exactly one egress policy for its whole
# lifetime, with no install-time phase (SPEC-v2 §5.2). A create-time
# `uv tool install` would therefore leave pypi.org and files.pythonhosted.org
# reachable by the agent for as long as the sandbox lives, just to fetch
# something once. Installing here keeps `permissions.network.allow` down to
# what tau actually talks to while it runs.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# pi/hermes-agent/openclaw/kiro.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# `:shell`, not `:shell-docker`. tau executes its tool calls in the sandbox
# itself -- `tau_coding/local_backends.py` names no container runtime -- so a
# Docker engine would be weight nothing in this kit uses. No
# com.docker.sandboxes.start-docker label for the same reason: requesting
# Docker mode over a base with no engine yields a sandbox started with nothing
# to run.

# Rolling updates by design: this image tracks whatever is current on PyPI, and
# the nightly scheduled run of build-and-publish-kits.yml rebuilds against it.
# The ADD below is what makes that work under CI's layer cache -- BuildKit
# re-fetches the URL on every build to compute its digest, so the install layer
# re-runs exactly when the fetched document changes and is a cache hit
# otherwise. Without it the unchanging RUN line would hit the gha cache forever
# and the nightly rebuild would ship a stale binary.
#
# PyPI has no `latest` path segment the way npm has dist-tags, so the URL is
# the package-level document and the release is read out of `info.version`
# below. TAU_AI_VERSION pins the install to a specific release instead; the ADD
# still refreshes either way, so a pinned build re-runs its install layer
# whenever any tau release is published. Wasteful, not wrong -- it reinstalls
# the version it was told to.
ARG TAU_AI_VERSION=""
ADD --chmod=644 https://pypi.org/pypi/tau-ai/json /tmp/tau-pypi.json

# Installed as `agent` rather than root, for two reasons that both surface
# late. Ownership: `uv tool upgrade` runs as agent inside the sandbox and would
# hit EACCES on a root-owned tool directory. PATH: a root `uv tool install`
# lands in /root/.local/bin, which is neither on the agent user's PATH nor
# readable by it (/root is 0700), so the whole failure presents as a bare
# `tau: command not found` with the binary sitting right there on disk.
#
# UV_PYTHON_DOWNLOADS=never is what makes an incompatible release a build
# failure. uv's default is to FETCH a managed interpreter when no installed one
# satisfies `requires-python`, so a future tau requiring, say, 3.15 would not
# fail here -- it would silently add ~50 MB of Python to every sandbox and stop
# using the template's interpreter. Denying the download turns that into a
# failed install, which is the same protection npm-based kits get from their
# `--version` gate (npm only WARNS on an engines mismatch, so pi has to execute
# the binary to catch it; uv errors outright once it cannot paper over the
# mismatch).
#
# The version gate is therefore aimed at the other failure: a release whose
# entry point throws on import. It is invoked by absolute path because
# `uv tool install` puts the shim in ~/.local/bin, and relying on PATH here
# would make a base-image PATH change read as a missing binary. Either way it
# fails the build, and so blocks the nightly publish, rather than shipping.
#
# /tmp/tau-pypi.json is deliberately not removed: it lives in the ADD's own
# layer, so deleting it here would only add a whiteout on top of the ~55 KB
# that ships either way.
# `jq -e` rather than a plain read: without it a missing or renamed key yields
# the string "null", which would sail past the non-empty check below and turn
# into `uv tool install tau-ai==null`. With -e, jq exits non-zero on a null
# result and the build stops here.
USER agent
WORKDIR /home/agent
ENV UV_PYTHON_DOWNLOADS=never
RUN set -eu; \
    version="${TAU_AI_VERSION:-$(jq -er '.info.version' /tmp/tau-pypi.json)}"; \
    [ -n "$version" ]; \
    uv tool install "tau-ai==${version}"; \
    "$HOME/.local/bin/tau" --version

# ~/.local/bin is on PATH in this image, but not in every context that may
# invoke the binary -- startup commands and some exec paths run with a minimal
# PATH. A symlink somewhere always on PATH costs nothing. /usr/local/bin is
# root-owned, so this step goes back to root.
USER root
RUN ln -sf /home/agent/.local/bin/tau /usr/local/bin/tau

# Overrides the value inherited from the base image, which describes the base
# rather than this image: left inherited it would read "shell", and sbx would
# report this image's agent as "shell". It must be the kit's own name.
LABEL com.docker.sandboxes.flavor="tau"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
# Bare `tau`, deliberately: which provider to start on is the KIT's policy
# (spec.yaml pins one in its entrypoint), not a property of the image. Baking a
# provider in here would make `docker run` and a kit-created sandbox disagree
# the moment the kit changes its mind.
CMD ["tau"]
