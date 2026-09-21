# syntax=docker/dockerfile:1.7
# OpenHands as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: `uv tool install` has no --prefix. It writes a tool venv under
# $XDG_DATA_HOME/uv/tools and downloads a standalone CPython 3.12 under
# .../uv/python, and every console-script shebang and every venv `home` record
# it writes names those absolute paths. Installing somewhere else and moving
# the tree afterwards would leave a shebang pointing at a directory the
# composed sandbox does not have. So this takes the shape the guide prescribes
# for exactly that case -- run the unmodified install on the workload's own
# base, with HOME already at /home/agent (the sandbox runtime's own home, so
# the baked paths are correct when the overlay lands), then copy the specific
# resulting paths into a scratch overlay.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

USER root
# Ownership starts at /out/home/agent, not /out/home: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent/.local /out/etc/profile.d /out/usr/local/bin \
 && chown -R agent:agent /out/home/agent

# The kit's `version` arg arriving as a build arg -- openhands-mixin.yaml
# declares it with `buildArg: OPENHANDS_VERSION`, validates its shape, and
# expands the same value into `provides: ["openhands@..."]`. Deliberately no
# default here: the descriptor is the single source of the pin.
ARG OPENHANDS_VERSION

# The pinned release's own PyPI metadata. The URL now always names a version --
# it used to omit that segment, because PyPI has no literal "latest" and an
# absent version returns the newest release, which is what the empty default
# meant. Pinning removes that branch: this fetch 404s the build if the pinned
# release does not exist, and the `info.version` read out of it below is PyPI's
# canonical spelling of the pin.
ADD --chmod=644 https://pypi.org/pypi/openhands/${OPENHANDS_VERSION}/json /tmp/openhands-release.json

USER agent
WORKDIR /home/agent

# The install, unmodified from the workload recipe: `openhands` (the V1
# terminal CLI, distinct from `openhands-ai` and `openhands-sdk`) pins
# requires-python to 3.12.x, so `--python 3.12` makes uv download a standalone
# CPython 3.12. The requirement is `openhands==<version>`, an exact specifier
# rather than a range, so what uv resolves is the release the descriptor
# promised. `openhands --version` is the build-time gate -- a broken release
# fails the build instead of shipping a non-starting agent.
RUN set -eu; \
    version="$(grep -oP '"version":\s*"\K[^"]+' /tmp/openhands-release.json)"; \
    [ -n "$version" ]; \
    uv tool install --python 3.12 "openhands==${version}"; \
    "$HOME/.local/bin/openhands" --version

# The specific resulting paths: the tool venv and the managed interpreter
# under ~/.local/share/uv, and the launcher symlink uv wrote into
# ~/.local/bin. Both ends of that symlink land at the same absolute paths
# here, so it resolves in the overlay.
RUN set -eu; \
    mkdir -p /out/home/agent/.local/share /out/home/agent/.local/bin; \
    cp -a /home/agent/.local/share/uv /out/home/agent/.local/share/uv; \
    cp -a /home/agent/.local/bin/openhands /out/home/agent/.local/bin/openhands

# The kit's own scripts.
#
# MIGRATION NOTE: this tree is a copy of ../openhands/files/, not a reference
# to it. A kit's build context is rooted at its own descriptor's directory and
# may not escape it (SPEC-v3 §4), so a sibling kit's assets are unreachable
# from here. The two must move together -- see this kit's README. Copied
# without an exec bit, as the workload copies them, because
# openhands-anthropic-auth.sh is invoked through `sh`.
# No --chown here: BuildKit applies it to every parent it creates, which
# stamps uid 1000 onto /out/home and hands /home away on every base this
# composes onto. The `chown -R /out/home/agent` below starts one level too
# deep to undo that, so the copy leaves parents root-owned and the chown
# owns exactly the agent home and its contents.
COPY files/home/ /out/home/agent/

USER root

# openhands-start.sh additionally lands as a 0755 launcher on PATH. Unlike the
# hermes kit -- where the equivalent wrapper only sourced an env file a login
# shell already picks up -- this one is load-bearing beyond entrypoint
# plumbing: it passes `--override-with-envs`, without which openhands ignores
# LLM_API_KEY/LLM_MODEL entirely and either falls back to a persisted
# ~/.openhands/agent_settings.json or opens its interactive first-run settings
# form. The resolved credential reaches the agent through this flag or not at
# all, so the mixin ships the wrapper rather than asking a user to remember it.
#
# The /usr/local/bin/openhands shim is a bin shim rather than a profile.d PATH
# export: ~/.local/bin is on PATH on the shell templates, but a mixin lands on
# any base and /usr/local/bin is on every one of them.
RUN set -eu; \
    install -m 0755 /out/home/agent/.local/bin/openhands-start.sh /out/usr/local/bin/openhands-start; \
    ln -s /home/agent/.local/bin/openhands /out/usr/local/bin/openhands; \
    chown -R 1000:1000 /out/home/agent

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead.
#
# Not LLM_MODEL: openhands-anthropic-auth.sh is the sole source of that
# variable, and it deliberately leaves it unset when there is no Anthropic
# credential to resolve or a persisted agent_settings.json already exists --
# a static default here would apply regardless and silently override either.
COPY <<'EOF' /out/etc/profile.d/openhands-env.sh
export OPENHANDS_SUPPRESS_BANNER=1
export SANDBOX_TYPE=local
EOF

# The overlay: the uv tool venv, its managed interpreter and the kit's
# scripts, landing on any base. No ENTRYPOINT -- the base workload's launch
# command stays.
FROM scratch
COPY --from=build /out /
