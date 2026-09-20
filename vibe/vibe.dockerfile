# syntax=docker/dockerfile:1

# The vibe workload's content. This is the v2 kit's Dockerfile: v2 published
# it as docker.io/sbx/vibe-image:latest and pointed `sandbox.image` at the
# result, while a v3 workload's layers *are* the root filesystem -- so the
# intermediate publish disappears and this recipe builds the kit directly.
# v2's environment.variables and sandbox.entrypoint land at the bottom, in
# the image config that already owns runtime config.
#
# The base is a floating tag and Vibe is installed from a `latest` channel,
# which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# PyPI version of mistral-vibe: "latest", or an exact number such as 2.25.0 to
# pin the image to a known release. Not a kit arg: the descriptor's provide is
# unversioned precisely because the default floats, and a kit arg would have
# to pin.
ARG VIBE_VERSION=latest

# uv ships with the template at /usr/local/bin/uv, and `uv tool install` puts
# the executables in ~/.local/bin, which is already on the template's PATH --
# so the ENTRYPOINT below can stay the bare name `vibe`.
USER agent
RUN set -ex; \
    if [ "${VIBE_VERSION}" = "latest" ]; then SPEC="mistral-vibe"; else SPEC="mistral-vibe==${VIBE_VERSION}"; fi; \
    uv tool install "${SPEC}"; \
    vibe --version

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
