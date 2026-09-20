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

# Upstream's tagged releases land roughly weekly, sometimes with same-week
# patch releases (v0.91.0, v0.91.1, v0.91.2 within four days) -- frequent
# enough that a rolling `latest`, rebuilt nightly, is the right model rather
# than a hand-maintained pin. Re-check the cadence before trusting this
# reasoning to still hold. It is also why the descriptor declares no version
# arg and an unversioned provide: there is no pin here for one to reference.
#
# The feed is not parsed for a version string -- `apt-get install crush`
# below always resolves whatever Charm's own apt repo currently serves, and
# Charm publishes the .deb and the GitHub release from the same pipeline, so
# a new release entry here is a reliable signal that the apt repo has moved
# too. What the ADD buys is cache invalidation: BuildKit re-fetches the URL
# on every build to compute its digest, so this layer -- and every RUN after
# it -- re-runs whenever the feed's content has changed since the last build.
# That happens on every tagged release, and at least once a day regardless:
# upstream also re-cuts a rolling `nightly` pre-release entry every night, so
# the digest moves daily even between stable releases. A same-day cache hit
# is still possible, but the scheduled nightly publish always builds without
# cache anyway, and the cost of a same-day miss is only one redundant apt
# install.
#
# The feed is served by github.com, not the API: it sits outside the per-IP
# unauthenticated quota hosted CI runners share on api.github.com, and
# BuildKit's URL fetch carries no token to lift that limit anyway. The feed
# is roughly 150 KB and ships in the image -- it lands before the apt install
# layers, so a later-layer delete would only add a whiteout on top of its own
# layer.
ADD --chmod=644 https://github.com/charmbracelet/crush/releases.atom /tmp/crush-releases.atom

# GPG key, apt repository, and install run once here at image-build time,
# where they have ordinary internet access. repo.charm.sh (the apt index and
# GPG key) and the Gemfury-fronted S3 bucket its index redirects package
# downloads to are both build-time-only: neither is a credential inject
# domain, so neither belongs in the kit's runtime allow list.
USER root
RUN set -euo pipefail; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg; \
    echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
      > /etc/apt/sources.list.d/charm.list; \
    apt-get update -qq; \
    apt-get install -y -qq crush; \
    rm -rf /var/lib/apt/lists/*

# `crush --version` is the build-time gate: it actually runs the installed
# binary, so a release apt cannot install, or whose binary fails to start,
# fails the build -- and so the nightly publish -- instead of shipping a
# non-starting agent.
RUN crush --version

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
