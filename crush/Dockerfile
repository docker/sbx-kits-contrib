# syntax=docker/dockerfile:1.7
# Base image for the `crush` sandbox kit.
#
# Crush is pre-baked so sandbox creation is fast and so its install-time
# fetches (Charm's apt signing key, the apt index, and the .deb payload
# itself) never have to sit in this kit's *runtime* network allowlist -- the
# engine enforces one allowlist per sandbox and cannot distinguish a
# build-time fetch from one the running agent might make.
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

# Crush has no tool of its own that talks to a Docker engine: LSPs and MCP
# servers are commands the user adds via `crushrc` and Crush execs them
# directly, it does not start containers for them. Docker stays available
# anyway, on the same basis as pi/openclaw/kiro/copilot -- the agent's own
# tools don't need it, but the user's project underneath it might (a
# docker-compose test suite, a container build) -- rather than picking a
# dockerless base for a reason that is about Crush, not the sandbox.

# Upstream's tagged releases (checked via the GitHub releases API) land
# roughly weekly, sometimes with same-week patch releases (v0.91.0, v0.91.1,
# v0.91.2 within four days) -- frequent enough that a rolling `latest`,
# rebuilt nightly, is the right model rather than a hand-maintained pin.
# Re-check the cadence before trusting this reasoning to still hold.
# CRUSH_REF selects the GitHub releases API path segment: "latest" (default)
# resolves upstream's newest tagged release, or "tags/vX.Y.Z" to pin one.
#
# The JSON is not parsed for a version string -- `apt-get install crush`
# below always resolves whatever Charm's own apt repo currently serves, and
# Charm publishes the .deb and the GitHub release from the same pipeline, so
# a new release tag here is a reliable signal that the apt repo has moved
# too. What the ADD buys is cache invalidation: BuildKit re-fetches the URL
# on every build to compute its digest, so this layer -- and every RUN after
# it -- is a cache hit when upstream has not published since the last build,
# and re-runs, picking up the apt repo's new package, exactly when it has.
ARG CRUSH_REF=latest
ADD --chmod=644 https://api.github.com/repos/charmbracelet/crush/releases/${CRUSH_REF} /tmp/crush-release.json

# GPG key, apt repository, and install run once here at image-build time,
# where they have ordinary internet access. repo.charm.sh (the apt index and
# GPG key) and the Gemfury-fronted S3 bucket its index redirects package
# downloads to are both install-time-only: neither is a credential inject
# domain, so neither belongs in the kit's runtime allowlist.
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
# lands, which is what makes dropping the apt/GPG hosts from the runtime
# allowlist correct rather than merely convenient.

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell-docker" rather than "crush".
LABEL com.docker.sandboxes.flavor="crush"

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this
# repository does not own.
LABEL com.docker.sandboxes.start-docker="true"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["crush", "--yolo"]
