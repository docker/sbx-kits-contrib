# syntax=docker/dockerfile:1

# The template carries everything this kit ships: the toolchain, the non-root
# `agent` user, and a Docker engine. The recipe adds no content, only the
# runtime contract and the labels that describe it. A workload must have a
# recipe, which is why this file exists at all.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# An ARG declared before the first FROM is visible only to FROM lines, so the
# LABEL below needs it re-declared inside the stage.
ARG BASE_IMAGE

# USER and WORKDIR are inherited rather than re-declared: sbx@1 needs an image
# config naming a user the host resolves to a uid, gid and home, and a
# re-pointed BASE_IMAGE must still land on a non-root `agent`.

# A request to the runtime, not a description of the image: it asks for
# privileged mode, a block volume at /var/lib/docker and dockerd at boot.
# Inherited from the base, re-declared so the value is owned here.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as an agent identifier and surfaces it as an image's
# Agent, so it must name this kit rather than the base it was built on.
LABEL com.docker.sandboxes.flavor="shell"

# Informational, and overriding the base's own value. The base is a floating
# tag rebuilt nightly, so this is the one place the image records its input.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# The launch contract. A v3 workload takes its binary from ENTRYPOINT[0] and
# its arguments from the rest plus CMD, and a kit with neither is rejected as
# having no command, so the login shell is spelled out here rather than left
# to the base's bare `CMD ["bash"]`. `-l` is what sources ~/.bash_profile, and
# through it ~/.bashrc, where the template sets the prompt.
ENTRYPOINT ["bash"]
CMD ["-l"]
