# syntax=docker/dockerfile:1

# Base image for the `cursor` sandbox kit.
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

# Cursor Agent has no interactive-auth wrapper to install (unlike kiro's
# device-flow launcher) — the sandbox proxy resolves the `cursor` credential
# declared in spec.yaml and injects it per request. So this is just the
# upstream install script, verbatim from https://cursor.com/cli.
#
# It installs into /home/agent/.local/bin/cursor-agent. That path is what
# spec.yaml's entrypoint names, in full: the directory is on this image's PATH,
# but the runtime owns PATH and the entrypoint is exec'd rather than run
# through a login shell, so the kit does not rely on the lookup succeeding.
#
# Two departures from the vendor's published one-liner, both about failing
# closed rather than open:
#
#   - `-L`. `-f` does not treat a 3xx as an error, so without `-L` a redirect
#     would pipe an empty body into bash, bash would exit 0, and `pipefail`
#     would see nothing wrong — an image with no agent in it that built
#     "successfully".
#   - the `test -x` afterwards. The installer's own failure paths are the other
#     half of the same problem: a completed install command proves an exit
#     code, not an installed binary. Nothing else in this repo's local
#     verification asserts the binary exists, so assert it here.
RUN <<EOF
set -exo pipefail
curl -fsSL https://cursor.com/install | bash
test -x /home/agent/.local/bin/cursor-agent
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
# the one being run. So it must be the kit's own name: `cursor`.
LABEL com.docker.sandboxes.flavor="cursor"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# Absolute, matching spec.yaml's entrypoint, for the same reason: no dependence
# on PATH. Note this CMD carries no --yolo — the kit's entrypoint supplies it,
# so plain `docker run` of this image keeps the agent's own approval prompts.
CMD [ "/home/agent/.local/bin/cursor-agent" ]
