# syntax=docker/dockerfile:1

# Base image for the `devin` sandbox kit.
#
# Requires egress to `cli.devin.ai` (install.sh) and `static.devin.ai` (the
# manifest and the versioned bundle the script fetches) at build time.
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

# Runs as the base image's default user (`agent`, uid 1000), which matters:
# install.sh is a per-user installer with no --prefix, so everything below
# lands under /home/agent and is owned by the user that will run it.
RUN <<EOF
set -ex

# install.sh ends by running `devin setup`, an interactive wizard that cannot
# complete without a TTY and exits non-zero ("Login canceled"). Because that is
# the script's last command it is also the script's exit status, so a clean
# install reports failure here and `set -o pipefail` in the base shell would
# abort the build.
curl -fsSL https://cli.devin.ai/install.sh | bash || true

# ...so assert the outcome instead of trusting the status that was just
# discarded. A genuine download or checksum failure still fails the build here,
# which is the only reason the `|| true` above is safe.
devin --version

# The installer's `devin` is the only one on PATH, and the auth wrapper has to
# take that name for `sandbox.entrypoint` to stay `[devin, ...]`. Expose the
# real CLI as `devin-cli` first.
#
# `readlink` without -f on purpose: it copies the symlink's TARGET
# (…/_versions/current/bin/devin) rather than resolving it to today's version
# directory, so `devin-cli` keeps floating with `current` instead of pinning
# the version installed at build time.
ln -s "$(readlink /home/agent/.local/bin/devin)" /home/agent/.local/bin/devin-cli

# Remove the installer's symlink before the COPY below replaces it. Without
# this, COPY resolves the existing symlink and writes the wrapper through it,
# overwriting the real CLI binary inside the version directory.
rm /home/agent/.local/bin/devin
EOF

# The launcher the sandbox entrypoint resolves as `devin`: it checks
# authentication state, drops into the manual token flow when there is none,
# then hands off to devin-cli.
COPY --chown=agent:agent --chmod=0755 start.sh /home/agent/.local/bin/devin

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
# the one being run. So it must be the kit's own name: `devin`.
LABEL com.docker.sandboxes.flavor="devin"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

CMD [ "devin" ]
