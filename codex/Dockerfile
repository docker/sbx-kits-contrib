# syntax=docker/dockerfile:1

# Base image for the `codex` sandbox kit.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a kind:sandbox kit names a single sandbox.image, so a second image
# would be unreachable without a second kit to consume it.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# CODEX_HOME. Created here rather than only in the kit's install hook so the
# directory exists — and is owned by `agent`, the USER inherited from the base —
# before anything else in the container start sequence can create it as root.
# The install hook still does its own `mkdir -p`, which makes this belt and
# braces rather than the only guarantee.
RUN mkdir -p /home/agent/.codex

# xdg-utils, for the `xdg-open` that this kit's BROWSER variable names.
#
# The base image ships neither xdg-open nor xdg-settings, so without this layer
# BROWSER points at a binary that does not exist and every "open this link for
# you" attempt dies with a command-not-found. This kit builds its own image
# precisely so it can install what the agent needs, so it installs it.
#
# --no-install-recommends is load-bearing rather than habitual here: the
# recommends are the desktop-integration half of the package
# (libfile-mimeinfo-perl, libnet-dbus-perl, libx11-protocol-perl, x11-utils,
# x11-xserver-utils) and pull in an X11 dependency tree a headless sandbox has
# no use for. Skipping them leaves xdg-utils with no dependencies at all: one
# architecture-independent package of shell scripts, well under a megabyte.
#
# BROWSER=xdg-open does not make xdg-open re-invoke itself: Debian and Ubuntu
# patch the script to strip its own name out of $BROWSER before consulting it,
# so it falls through to the browser list instead of recursing.
#
# Deliberately placed above the npm layer below. That layer floats on
# `@openai/codex@latest` and re-runs on every nightly rebuild; this one has
# nothing to do with which Codex version is installed, and above it stays a
# cache hit.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends xdg-utils && \
    rm -rf /var/lib/apt/lists/* && \
    command -v xdg-open
USER agent

# Codex's npm package is ~370 MB, so the default fetch timeout is not enough on
# a slow or proxied network: raise it and retry rather than failing the whole
# image build on one stalled request.
#
# --include=optional is load-bearing, not hygiene. The platform-specific native
# binary (@openai/codex-linux-x64 and friends) ships as an optional dependency,
# so omitting the flag produces an install that exits 0 and leaves no working
# binary behind.
#
# Plain `npm`, deliberately. The built-in agent's image drives this install
# through `corepack npm` and then tries to `corepack disable npm`; both halves
# are worth dropping here:
#
#   * `corepack npm` downloads an unpinned npm over the network on every build
#     and then warns that that npm does not support this image's Node — a
#     warning today, a hard failure whenever npm decides to enforce it.
#   * `corepack disable npm` cannot succeed anyway. This layer runs as the
#     non-root `agent` user inherited from the base, so unlinking the
#     root-owned /usr/bin/npm fails EACCES; the `|| echo` fallback next to it
#     is what keeps the build green. It has nothing to remove either, because
#     nothing in this image ever ran `corepack enable`.
#
# The end state that actually matters is unchanged and verified below: the real
# apt-installed /usr/bin/npm is the npm on PATH at runtime, which is what Codex
# needs — its self-updater spawns `npm` directly and dies with ENOENT against a
# corepack shim.
#
# `codex --version` last, deliberately: an install command's exit code says
# only that npm exited 0, not that a usable binary landed. This asserts the
# outcome instead of trusting the exit code.
RUN npm install -g @openai/codex@latest \
      --include=optional \
      --fetch-timeout=300000 \
      --fetch-retries=3 \
      --fetch-retry-mintimeout=60000 \
 && codex --version \
 && command -v npm

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `codex`.
LABEL com.docker.sandboxes.flavor="codex"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

CMD [ "codex" ]
