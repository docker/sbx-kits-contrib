# syntax=docker/dockerfile:1
# The content of the `crush` workload kit -- the v2 Dockerfile that built
# docker.io/sbx/crush-image:latest, now the kit's own recipe. A v3 workload's
# layers are the root filesystem, so there is no separate published base image
# and no sandbox.image pointing at one.
#
# Crush is baked in rather than installed at sandbox-create time, which is what
# keeps its install-time fetches (Charm's apt signing key, the apt index, and
# the .deb payload itself) out of the kit's network policy entirely: a build
# runs before any phase the policy scopes, so neither allow list has to admit
# repo.charm.sh.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Crush's own tool set (bash, edit, view, grep, glob, fetch, download --
# internal/agent/tools/ upstream) has nothing that launches or manages
# containers; LSPs and MCP servers are commands the user configures and Crush
# execs them directly. The plain base is correct here.

# The pin, handed in by the frontend from the descriptor's `version` arg
# (buildArg: CRUSH_VERSION). The default is repeated here so a plain
# `docker build` of this file still works; the descriptor is the authority
# and the two move together. See crush.yaml for how the value is read out of
# Charm's package index and what makes an apt pin durable here.
ARG CRUSH_VERSION=0.95.0

# GPG key, apt repository, and install run once here at image-build time,
# where they have ordinary internet access. repo.charm.sh (the apt index and
# GPG key) and the Gemfury-fronted S3 bucket its index redirects package
# downloads to are both build-time-only: neither is a credential inject
# domain, so neither belongs in the kit's runtime allow list.
#
# `crush=${CRUSH_VERSION}` rather than `crush`: an exact apt selector, which
# fails the build outright when the index cannot serve that version instead of
# quietly installing a different one. That failure mode is the point -- the
# descriptor publishes `crush@${CRUSH_VERSION}`, so an install that silently
# slid to another release would make the published provide false.
#
# The apt index used to be fetched here as a GitHub releases.atom `ADD`, purely
# so BuildKit's daily digest check would bust the cache and pull whatever was
# newest. A pinned install wants the opposite: the cache key is now the pin
# itself, so a rebuild that changes nothing installs the same release, and the
# feed fetch (150 KB, shipped in the image) is gone with the floating install
# it served.
USER root
RUN set -euo pipefail; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg; \
    echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
      > /etc/apt/sources.list.d/charm.list; \
    apt-get update -qq; \
    apt-get install -y -qq "crush=${CRUSH_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

# The build-time gate, and the check that keeps the descriptor honest: it runs
# the installed binary, so a release apt cannot install or whose binary fails
# to start fails the build instead of shipping a non-starting agent -- and it
# compares what the binary reports against the pin, so a Charm package whose
# contents disagree with its package version fails here rather than publishing
# `crush@${CRUSH_VERSION}` over content that is not that release.
RUN set -eu; \
    reported="$(crush --version)"; \
    echo "crush --version: ${reported}"; \
    case "${reported}" in \
      *"${CRUSH_VERSION}"*) ;; \
      *) echo "pin mismatch: descriptor says ${CRUSH_VERSION}, binary reports '${reported}'" >&2; exit 1 ;; \
    esac

# Crush is a single statically-linked Go binary -- `go install
# github.com/charmbracelet/crush@latest` is one of upstream's own install
# paths -- with no runtime dependency-fetch path of its own to seal off: LSPs
# and MCP servers are commands the user configures and Crush execs them, it
# does not install them. The binary is already a closed set once this layer
# lands, which is what makes leaving the apt/GPG hosts out of the runtime
# allow list correct rather than merely convenient.

# OVERRIDES the value inherited from the base image, which describes the
# base rather than this image. Not optional: sbx reads it as the image's
# agent identifier, and left inherited it would report "shell" rather than
# "crush".
LABEL com.docker.sandboxes.flavor="crush"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
# MIGRATION NOTE: v2's Dockerfile ended at `WORKDIR /home/agent`, which was
# only ever the `docker run` working directory -- the v2 engine mounted the
# workspace wherever it chose. Under sbx@1 the image's working directory *is*
# where the host places the workspace, so it moves to the conventional sibling
# of $HOME rather than mounting the user's checkout over the agent's home.
WORKDIR /home/agent/workspace

# MIGRATION NOTE: v2 split the launch across two fields the engine recombined
# -- `sandbox.entrypoint: [crush]` and `sandbox.command.default: [--yolo]` --
# and the Dockerfile's own `CMD ["crush", "--yolo"]` was dead for sandbox
# launch, since the spec's values won. In v3 the image config is the contract,
# and ENTRYPOINT + CMD are the slots those two fields map onto one for one, so
# the effective argv is unchanged. It is also what makes the agent-sessions
# prompt tail land as `crush --yolo run <prompt>`.
ENTRYPOINT ["crush"]
CMD ["--yolo"]
