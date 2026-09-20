# syntax=docker/dockerfile:1
# The content of the `amp` workload kit. The v2 kit shipped no Dockerfile: it
# pointed sandbox.image straight at a published template and installed Amp
# with a create-time hook. A v3 workload's layers are its root filesystem, so
# it must have content -- this recipe is the minimal statement of what v2 said,
# and nothing more.
#
# The base is v2's sandbox.image carried over verbatim, the `-docker` variant
# included: swapping it for a different template would change what the sandbox
# ships underneath the agent.
FROM docker/sandbox-templates:shell-docker

# The platform floor's user, restated rather than inherited: sbx@1 requires
# the image config to declare a non-empty user for the host to honor, and an
# inherited value is the base's statement rather than this kit's.
USER agent
# Where the host places the workspace under sbx@1. v2 had no Dockerfile and so
# no working directory of its own; this is the conventional sibling of $HOME
# that leaves the agent's home free for the tooling Amp installs into it.
WORKDIR /home/agent/workspace

# v2's sandbox.entrypoint. Amp itself is installed by the descriptor's
# lifecycle install hook, which the host finishes before this entrypoint first
# runs -- so the binary this names exists by the time it is launched, exactly
# as it did in v2.
#
# v2 declared no environment.variables, so this image sets no ENV.
ENTRYPOINT ["amp", "--dangerously-allow-all"]
