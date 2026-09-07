# syntax=docker/dockerfile:1.7
# Base image for the `junie` sandbox kit.
#
# Junie is pre-baked so sandbox creation is fast and so its install-time
# fetches (the vendor install script, the update-info feed it resolves a
# version against, and the GitHub-hosted release zip) never have to sit in
# this kit's *runtime* network allowlist -- the engine enforces one
# allowlist per sandbox and cannot distinguish a build-time fetch from one
# the running agent might make.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# hermes-agent/pi/openclaw/kiro/copilot.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Junie's own docs (README, junie.jetbrains.com) describe no Docker-backed
# tool of its own. Docker stays available anyway, on the same basis as
# pi/openclaw/kiro/copilot -- the agent's own tools don't need it, but the
# user's project underneath it might (a docker-compose test suite, a
# container build) -- rather than picking a dockerless base for a reason
# that is about Junie, not the sandbox.

# install.sh installs into $HOME/.local -- run it as the user the sandbox
# actually runs as, so the installed tree is agent-owned rather than root's.
USER agent
WORKDIR /home/agent

# The stable ("release") channel -- what junie.jetbrains.com/install.sh
# installs by default, and what this kit supports -- published 65 builds
# between 2026-02-26 and 2026-09-07 (JetBrains/junie's GitHub releases),
# unevenly spaced but averaging better than two a week. That is frequent
# enough that a rolling `latest`, rebuilt nightly, is the right model rather
# than a hand-maintained pin. Re-check the cadence before trusting this
# reasoning to still hold.
#
# update-info.jsonl is the exact resource install.sh itself parses to resolve
# "the newest build for this platform" -- ADDing it here buys nothing the
# installer doesn't already do, except cache invalidation: BuildKit re-fetches
# the URL on every build to compute its digest, so this layer -- and the RUN
# below -- is a cache hit when the stable channel has not moved since the
# last build, and re-runs, picking up the new build, exactly when it has.
ADD --chmod=644 https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl /tmp/junie-update-info.jsonl

# The vendor's own installer: same one-line install junie.jetbrains.com
# documents, just run at image-build time instead of sandbox-create time.
# JUNIE_VERSION is deliberately left unset so this always resolves the
# stable channel's current build rather than a version this Dockerfile would
# otherwise have to keep in sync by hand.
#
# `set -o pipefail` first: without it, a curl failure feeding an empty stdin
# to `bash` still exits 0 (bash treats empty input as a no-op script), so the
# RUN step would report success on a network failure that installed nothing.
# The gate below still catches that case, but failing here is what actually
# names the broken step in the build log.
RUN set -o pipefail; curl -fsSL https://junie.jetbrains.com/install.sh | bash

# `junie --version` is the build-time gate: it actually runs the installed
# binary, so a build the installer cannot complete, or that fails to start,
# fails the image build -- and so the nightly publish -- instead of shipping
# a non-starting agent.
#
# ~/.local/bin is where the installer's shim lands; it is not guaranteed to
# be on PATH for a RUN step that starts a fresh non-login shell.
RUN "$HOME/.local/bin/junie" --version

# The installed shim itself would otherwise reach for network on every
# launch: it defers to the binary's own auto-update service, which -- left
# alone -- checks the update-info feed above and stages a new build for the
# shim to apply on next launch (JetBrains/junie templates/junie.shim.sh,
# apply_pending_update). JUNIE_SKIP_UPDATE_CHECK is the binary's own switch
# for this (SystemOptionsGroup / AutoUpdateService, honored by the shim's
# one-shot channel-launch path too) -- baking it here is what makes this
# image's runtime network need actually closed rather than an approximation
# of one: nothing after this point calls out to check for, download, or
# stage a Junie update. `junie --eap` / `--nightly` / `--experimental`
# one-shot channel switching still calls out on its own regardless of this
# variable (it is a distinct, explicitly-requested feature, not a passive
# update check) and is outside this kit's supported surface -- its target
# hosts are not in permissions.network.allow.
ENV JUNIE_SKIP_UPDATE_CHECK=1

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell-docker" rather than "junie".
LABEL com.docker.sandboxes.flavor="junie"

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this
# repository does not own.
LABEL com.docker.sandboxes.start-docker="true"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

ENV PATH="/home/agent/.local/bin:${PATH}"
CMD ["junie"]
