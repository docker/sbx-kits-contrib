# syntax=docker/dockerfile:1

# The vibe workload's content. This is the v2 kit's Dockerfile: v2 published
# it as docker.io/sbx/vibe-image:latest and pointed `sandbox.image` at the
# result, while a v3 workload's layers *are* the root filesystem -- so the
# intermediate publish disappears and this recipe builds the kit directly.
# v2's environment.variables and sandbox.entrypoint land at the bottom, in
# the image config that already owns runtime config.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
# Vibe itself is not: the kit pins its release (see ARG VIBE_VERSION below),
# so a scheduled rebuild refreshes the base and leaves the agent where it is.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker

# MIGRATION NOTE: the install runs in a build stage, where the v2 recipe had a
# single one. mistral-vibe depends on miniaudio, which publishes no arm64 wheel,
# so uv builds it from source and needs a C++ compiler the template does not
# carry -- the v2 recipe therefore could only ever build for amd64, even though
# CI asked for both platforms. The compiler is installed here and stays behind
# in this stage, so the published kit does not carry a toolchain it never uses.
#
# Both stages are the same base and the install lands at the same absolute
# paths, which is what makes the copy below equivalent to what the v2
# single-stage build produced.
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg arriving as a build arg -- vibe.yaml declares it with
# `buildArg: VIBE_VERSION`, validates its shape, and expands the same value
# into `provides: ["vibe@..."]`. Deliberately no default here: the descriptor
# is the single source of the pin, and a second default in this file would be
# one more thing to keep in sync with it.
#
# MIGRATION NOTE: this used to default to the literal `latest`, with the
# nightly rebuild as the update mechanism. Bumping the descriptor's default is
# the update mechanism now -- the provide quotes it, so a floating install
# would make the kit claim a version it might not carry.
ARG VIBE_VERSION

USER root
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends g++; \
    rm -rf /var/lib/apt/lists/*

# uv ships with the template at /usr/local/bin/uv, and `uv tool install` puts
# the executables in ~/.local/bin, which is already on the template's PATH --
# so the ENTRYPOINT below can stay the bare name `vibe`.
#
# --managed-python is the other half of the arm64 fix, and it is not
# interchangeable with the compiler above: miniaudio's extension needs a
# compiler AND CPython's headers. The template's own python3.14 ships neither
# `pyconfig.h` nor an apt package that provides it -- there is no
# `python3-dev` candidate in its sources at all -- so uv downloads a managed
# interpreter that carries its headers. The version is pinned to 3.14 to match
# the interpreter the v2 image ran on, so this changes where Python comes from
# and not which Python it is.
#
# The requirement is `mistral-vibe==<version>`, an exact specifier rather than
# a range: what uv resolves is the release the descriptor promised, which is
# what makes the provide's version true of the built image. The `latest` branch
# this line used to carry is gone with the ARG's default.
#
# `vibe --version` last, as the build-time gate -- a release that does not run
# fails the build instead of shipping, and its output is the build log's record
# of what the pin resolved to.
USER agent
RUN set -ex; \
    uv tool install --managed-python --python 3.14 "mistral-vibe==${VIBE_VERSION}"; \
    vibe --version

FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# uv bakes absolute interpreter paths into the tool venv, so the tree has to
# land at exactly the path it was installed to. The final stage is the same
# base rather than scratch, so /home and /home/agent already exist with the
# ownership the platform floor expects and the copy only owns what it brings.
COPY --from=build --chown=agent:agent /home/agent/.local /home/agent/.local
USER agent

# Requests Docker-in-Docker from the runtime. Inherited from the base image,
# but re-declared so the value is owned here rather than depending on
# inheritance from an image this repository does not own. This stays a label:
# it is a request to the runtime, not a v3 capability.
LABEL com.docker.sandboxes.start-docker="true"

# sbx reads `flavor` as the image's agent identifier and surfaces it in the API,
# so it must be the kit's own name -- left inherited it would read
# "shell-docker" and sbx would report this image's agent as that.
LABEL com.docker.sandboxes.flavor="vibe"

# Informational only. Worth setting because the base is a floating tag rebuilt
# nightly: this is the one place the produced image records what it was built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's environment.variables, in the slot OCI already owns for static env.
#
# Vibe maps VIBE_<CONFIG_FIELD> onto its config schema, so the first two are
# the `enable_telemetry` / `enable_auto_update` fields of ~/.vibe/config.toml.
# No silent self-update inside the sandbox: the version is whatever the image
# ships, so a run is reproducible and needs no egress to PyPI.
# GIT_TERMINAL_PROMPT never blocks on a git credential prompt in a
# non-interactive session.
ENV VIBE_ENABLE_TELEMETRY=false \
    VIBE_ENABLE_AUTO_UPDATE=false \
    GIT_TERMINAL_PROMPT=0

WORKDIR /home/agent

# v2's sandbox.entrypoint, which read the kit's `agent` arg through
# `${{ kit.args.agent }}`. That arg now resolves at sandbox create rather
# than at build (see the MIGRATION NOTE in vibe.yaml), so it arrives as the
# VIBE_AGENT environment variable and the launch command reads it here. The
# `:-auto-approve` fallback restates the arg's default so a plain
# `docker run` of this image outside sbx still starts.
#
# --trust: the workspace is the user's own project, mounted by sbx, so Vibe's
#   trust prompt has nothing left to protect against and would only block a
#   non-interactive start.
# --agent: the sandbox is the security boundary, so the default profile lets
#   Vibe act without per-tool confirmation -- the same call the crush (--yolo)
#   and grok (--yolo) kits make. Narrow it with --kit-arg agent=ask.
#
# "$@" is what makes the agent-sessions prompt tail land after the flags:
# `sh -c` assigns the appended argv to the positional parameters, and $0 is
# the trailing `vibe` (a name for error messages, not an argument). Setting
# ENTRYPOINT also clears the CMD inherited from the base, and replaces the v2
# image's own `CMD ["vibe"]`.
ENTRYPOINT ["sh", "-c", "exec vibe --trust --agent \"${VIBE_AGENT:-auto-approve}\" \"$@\"", "vibe"]
