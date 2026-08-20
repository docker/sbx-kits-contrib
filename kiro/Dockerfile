# syntax=docker/dockerfile:1

# Base image for the `kiro` sandbox kit.
#
# Requires egress to both `cli.kiro.dev` (the install script) and
# `prod.download.cli.kiro.dev` (the versioned binary the script fetches).
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

# The launcher that the sandbox entrypoint resolves as `kiro`: it checks
# authentication state and drops into the device flow before handing off to
# kiro-cli. Installed as `kiro` so `sandbox.entrypoint` stays `[kiro, ...]`.
COPY --chown=agent:agent --chmod=0755 start.sh /home/agent/.local/bin/kiro

RUN <<EOF
set -ex
curl -fsSL https://cli.kiro.dev/install | bash

# Runs kiro-cli setup to have it create ~/.local/share/kiro-cli/data.sqlite3,
# which will potentially be managed in a Docker volume based on sandbox settings.
kiro-cli setup --no-confirm
EOF

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
# the one being run. So it must be the kit's own name: `kiro`, not `kiro-docker`,
# because only the warning path trims the suffix; the API path does not.
LABEL com.docker.sandboxes.flavor="kiro"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

CMD [ "kiro" ]
