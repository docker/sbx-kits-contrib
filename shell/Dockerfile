# syntax=docker/dockerfile:1

# Base image for the `shell` sandbox kit.
#
# The kit installs no agent: the sandbox template already carries the
# toolchain, the non-root `agent` user and a Docker engine. The image exists so
# the kit owns and pins what it ships instead of riding a floating tag it does
# not control, and so CI rebuilds it on the same nightly schedule as every
# other kit image here.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg visible only to FROM lines, so the LABEL below would expand
# to an empty string without this.
ARG BASE_IMAGE

# The shell configuration this image promises, established here rather than
# inherited so it survives a re-pointed BASE_IMAGE. Both halves are guarded on
# what they establish rather than on a marker string, so on a base that already
# carries them, which the default one does, this is a no-op instead of a second
# copy. `\W` is the directory basename rather than `\w`, the full path, which
# keeps the prompt readable in a deep workspace; the .bash_profile half is what
# makes it apply to the login shell the kit's `command: ["-l"]` starts.
#
# Runs as the image's own non-root user, which owns both files, so nothing here
# needs root or a chown afterwards.
RUN <<EOF
set -ex

if ! grep -q '^PS1=' /home/agent/.bashrc; then
    cat >> /home/agent/.bashrc <<'BASHRC'
PS1='\u@\h:\W\$ '
BASHRC
fi

if ! grep -q '\.bashrc' /home/agent/.bash_profile 2>/dev/null; then
    cat >> /home/agent/.bash_profile <<'PROFILE'

# Source .bashrc for login shells
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
PROFILE
fi
EOF

# Refresh the apt index at build time so `apt-get install` works in a fresh
# sandbox without a refresh first. The template ships an empty
# /var/lib/apt/lists, so without this the first install fails with "Unable to
# locate package".
#
# This is the whole reason the kit owns an image. As a startup hook it had to
# re-run on every boot and reach the network at launch; baked here it costs one
# layer (29 MB measured, on a 555 MB image) and CI rebuilds it nightly, so the
# index `latest` carries is at most a day old. A longer-lived pull can still
# meet a superseded version, and apt says so: it fails the install with a 404
# naming the package and telling you to run `apt-get update`.
USER root
RUN apt-get update -qq -y
USER agent

# A request to the runtime, not a description of the image: it asks for
# privileged mode, a block volume at /var/lib/docker and dockerd at boot.
# Inherited from the base, re-declared so the value is owned here.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as an agent identifier and surfaces it as an image's
# Agent, so it must be this kit's own name rather than the base's, which reads
# `shell-docker`.
LABEL com.docker.sandboxes.flavor="shell"

# Informational, overriding the base's own value, which records what the
# template was built on rather than what this image was. The base is a floating
# tag rebuilt nightly, so this is the one place the produced image records its
# real input.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Bare `bash`, with none of the kit's own arguments: the kit supplies `-l`, so
# a plain `docker run -it` of this image gets a non-login interactive shell
# rather than a sandbox-shaped launch.
CMD [ "bash" ]
