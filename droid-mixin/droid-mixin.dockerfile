# syntax=docker/dockerfile:1
# Overlay recipe for the droid mixin.
#
# Factory's installer is an opaque `curl | sh` with a user-scoped prefix: it
# lays the CLI under $HOME/.local and bakes that absolute path into what it
# writes. There is no --prefix to redirect it at, so the shape the guide
# prescribes for an unrelocatable install applies — run the unmodified install
# on the workload's own base, then copy the specific resulting paths into a
# scratch overlay.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so every absolute path the installer bakes is already correct when the
# overlay lands. Installing under a staging HOME and moving the tree
# afterwards would leave those paths pointing at a directory that does not
# exist in the composed sandbox.
FROM docker/sandbox-templates:shell-docker AS build

USER root
# Ownership is scoped to /out/home/agent, not /out: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent && chown -R agent:agent /out/home/agent

USER agent
ENV HOME=/home/agent
# The installer only symlinks onto an existing, writable PATH directory; it
# does not create one. Pre-creating ~/.local/bin is what makes its own
# symlink step succeed instead of falling through to rewriting .bashrc.
RUN set -eux; \
    mkdir -p "$HOME/.local/bin"; \
    curl -fsSL https://app.factory.ai/cli | sh

USER root
# `test -x` is the build-time gate: it pins the assumption that the installer
# lands under ~/.local/bin, so a change of prefix upstream fails the build
# here rather than shipping an overlay with no agent in it.
RUN set -eux; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    test -x /out/home/agent/.local/bin/droid; \
    mkdir -p /out/usr/local/bin; \
    ln -s /home/agent/.local/bin/droid /out/usr/local/bin/droid

# The bin shim above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them. v2 declared no environment.variables, so there is no env
# file to write beside it.

# The overlay: the agent's install tree and its bin shim, landing on any base.
# No ENTRYPOINT — the base workload's launch command stays, and the user runs
# `droid` from the shell.
FROM scratch
COPY --from=build /out /
