# syntax=docker/dockerfile:1.7
# Mistral Vibe as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: `uv tool install` has no --prefix. It writes a tool venv under
# $XDG_DATA_HOME/uv/tools and bakes absolute interpreter paths into every
# console-script shebang and into the venv's own `home` record. Installing
# somewhere else and moving the tree afterwards would leave a shebang
# pointing at a directory the composed sandbox does not have. So this takes
# the shape the guide prescribes for exactly that case -- run the unmodified
# install on the workload's own base, with HOME already at /home/agent (the
# sandbox runtime's own home, so the baked paths are correct when the overlay
# lands), then copy the specific resulting paths into a scratch overlay.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# PyPI version of mistral-vibe: "latest", or an exact number such as 2.25.0
# to pin the overlay to a known release. Not a kit arg: the descriptor's
# provide is unversioned precisely because the default floats.
ARG VIBE_VERSION=latest

USER root
# Ownership starts at /out/home/agent, not /out/home: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent/.local /out/etc/profile.d /out/usr/local/bin \
 && chown -R agent:agent /out/home/agent

# The install, unmodified from the workload recipe. uv ships with the
# template at /usr/local/bin/uv, and `uv tool install` puts the executables
# in ~/.local/bin. `vibe --version` is the build-time gate.
USER agent
WORKDIR /home/agent
RUN set -ex; \
    if [ "${VIBE_VERSION}" = "latest" ]; then SPEC="mistral-vibe"; else SPEC="mistral-vibe==${VIBE_VERSION}"; fi; \
    uv tool install "${SPEC}"; \
    vibe --version

# The specific resulting paths: the tool venv and any managed interpreter
# under ~/.local/share/uv, and the launcher symlink uv wrote into
# ~/.local/bin. Both ends of that symlink land at the same absolute paths
# here, so it resolves in the overlay.
RUN set -eu; \
    mkdir -p /out/home/agent/.local/share /out/home/agent/.local/bin; \
    cp -a /home/agent/.local/share/uv /out/home/agent/.local/share/uv; \
    cp -a /home/agent/.local/bin/vibe /out/home/agent/.local/bin/vibe

USER root

# v2's sandbox.entrypoint, as a launcher rather than an ENTRYPOINT.
#
# MIGRATION NOTE: a mixin sets no launch command, but v2's entrypoint was not
# just "run the binary" -- it carried two flags the kit's behaviour depends
# on, and one of them is the `agent` arg. Dropping them would leave that arg
# with nothing to read it and would put Vibe's trust prompt back in front of
# every start. So the flags ride a launcher instead, spelled exactly as the
# workload's ENTRYPOINT spells them:
#
#   --trust: the workspace is the user's own project, mounted by sbx, so
#     Vibe's trust prompt has nothing left to protect against and would only
#     block a non-interactive start.
#   --agent: the sandbox is the security boundary, so the default profile
#     lets Vibe act without per-tool confirmation. Narrow it with
#     --kit-arg agent=ask.
#
# The `:-auto-approve` fallback restates the arg's default, for a shell that
# reaches this script without the create-phase variable set.
COPY <<'EOF' /out/usr/local/bin/vibe-start
#!/bin/sh
exec vibe --trust --agent "${VIBE_AGENT:-auto-approve}" "$@"
EOF

# The bin shim below, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them.
RUN set -eu; \
    chmod 0755 /out/usr/local/bin/vibe-start; \
    ln -s /home/agent/.local/bin/vibe /out/usr/local/bin/vibe; \
    chown -R 1000:1000 /out/home/agent

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead.
#
# Vibe maps VIBE_<CONFIG_FIELD> onto its config schema, so the first two are
# the `enable_telemetry` / `enable_auto_update` fields of ~/.vibe/config.toml.
# No silent self-update inside the sandbox: the version is whatever the
# overlay ships, so a run is reproducible and needs no egress to PyPI.
COPY <<'EOF' /out/etc/profile.d/vibe-env.sh
export VIBE_ENABLE_TELEMETRY=false
export VIBE_ENABLE_AUTO_UPDATE=false
export GIT_TERMINAL_PROMPT=0
EOF

# The overlay: the uv tool venv, its bin shim and the launcher, landing on
# any base. No ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
