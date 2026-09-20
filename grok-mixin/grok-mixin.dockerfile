# syntax=docker/dockerfile:1
# Overlay recipe for the grok mixin.
#
# x.ai's install.sh is an opaque `curl | bash` with a user-scoped prefix: it
# lays the CLI under $HOME and symlinks it onto an existing PATH directory.
# There is no --prefix to redirect it at, so the shape the guide prescribes
# for an unrelocatable install applies — run the unmodified install on the
# workload's own base, then copy the specific resulting paths into a scratch
# overlay.
#
# This is also where the workload's setup hook went: ../grok installs at
# sandbox-create time, this kit installs at image-build time, which is why its
# descriptor declares no install phase and no lifecycle entry.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so the paths the installer bakes are already correct when the overlay lands.
FROM docker/sandbox-templates:shell-docker AS build

USER root
# Ownership is scoped to /out/home/agent, not /out: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent && chown -R agent:agent /out/home/agent

USER agent
ENV HOME=/home/agent
# The installer only symlinks `grok` onto an existing, writable PATH directory
# (~/.local/bin or /usr/local/bin); it does not create either. Without this
# mkdir it would silently fall through to rewriting .bashrc/.zshrc instead,
# which nothing in a sandbox sources.
RUN set -eux; \
    mkdir -p "$HOME/.local/bin"; \
    curl -fsSL https://x.ai/cli/install.sh | bash

USER root
# `test -x` is the build-time gate: it pins the assumption that the installer
# lands under ~/.local/bin, so a change of prefix upstream fails the build
# here rather than shipping an overlay with no agent in it.
RUN set -eux; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    test -x /out/home/agent/.local/bin/grok; \
    mkdir -p /out/usr/local/bin; \
    ln -s /home/agent/.local/bin/grok /out/usr/local/bin/grok

# The bin shim above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them. v2 declared no environment.variables, so there is no env
# file to write beside it.

# The overlay: the CLI's install tree and its bin shim, landing on any base.
# No ENTRYPOINT — the base workload's launch command stays, and the user runs
# `grok` from the shell. v2's `--yolo --no-auto-update` were entrypoint flags
# and belong to the workload; a user running `grok` here passes their own.
FROM scratch
COPY --from=build /out /
