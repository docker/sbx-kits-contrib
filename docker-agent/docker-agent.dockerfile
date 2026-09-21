# syntax=docker/dockerfile:1
# The content of the `docker-agent` workload kit -- the v2 Dockerfile that
# built docker.io/sbx/docker-agent-image:latest, now the kit's own recipe. A v3
# workload's layers are the root filesystem, so there is no separate published
# base image and no sandbox.image pointing at one.
#
# One image, no flavour suffix: the kit is its own content, so the
# Docker-in-Docker detail never reaches the user.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Docker Agent publishes one static binary per platform, so the release asset
# name has to be selected at build time. TARGETARCH is supplied by BuildKit and
# is the only correct source for it -- deriving it from `uname -m` would read
# the builder, not the target, and silently produce an amd64 binary in an arm64
# image under emulation.
ARG TARGETARCH

# Supplied by the descriptor's `version` arg, which owns the default and the
# accepted shape. No default here on purpose: the descriptor expands this same
# value into a versioned provide, so an unset value has to fail the build
# rather than resolve to whatever the newest release happens to be.
#
# It holds a bare version (`1.141.0`), not the tag -- SPEC-v3 §5.2 versions
# carry no `v` prefix, and the value has to be referenceable from `provides`.
# The `v` the tag needs is re-added below.
#
# MIGRATION NOTE: v2 spelled this `ARG DOCKER_AGENT_VERSION=""` and treated
# empty as "resolve the newest release from github.com's /releases/latest
# redirect". That branch is gone with the empty default; the redirect is still
# how the descriptor's default is established, but it is read by a human at
# bump time rather than by the build at build time, so the release the image
# carries is the one the descriptor names.
ARG DOCKER_AGENT_VERSION

# The agent self-updates in place (DOCKER_AGENT_AUTO_UPDATE below), which means
# rewriting its own binary, which it can only do where the agent user can write.
# So the binary lives under an agent-owned /opt path and /usr/local/bin carries
# a symlink for PATH lookups. Installing straight into /usr/local/bin -- where
# only root can write -- would leave self-update failing at run time.
#
# `test -x` at the end because a completed RUN proves an exit code, not an
# installed binary: curl's own failure modes and a truncated asset both need to
# fail the build here rather than ship an image with no agent in it.
RUN <<EOF
set -euxo pipefail

if [ -z "${DOCKER_AGENT_VERSION}" ]; then
    echo "DOCKER_AGENT_VERSION is empty. This kit publishes a versioned provide built from it, so there is no newest-release fallback: supply the kit's version arg, or --build-arg DOCKER_AGENT_VERSION=1.2.3 (no 'v')." >&2
    exit 1
fi

# The `v` the release tag carries and the arg does not. Kept here rather than
# in the arg so the arg stays a §5.2 version the descriptor can reference.
TAG="v${DOCKER_AGENT_VERSION}"

sudo install -d -o agent -g agent /opt/docker-agent/bin
curl -fsSL "https://github.com/docker/docker-agent/releases/download/${TAG}/docker-agent-linux-${TARGETARCH}" \
    -o /opt/docker-agent/bin/docker-agent
chmod 0755 /opt/docker-agent/bin/docker-agent
sudo ln -sf /opt/docker-agent/bin/docker-agent /usr/local/bin/docker-agent

test -x /opt/docker-agent/bin/docker-agent

# The asset name embeds the tag, so a wrong pin already fails at the download
# above -- but only because the tag does not exist. This asserts the stronger
# thing the provide claims: that the binary now on PATH reports this release.
#
# `version`, the subcommand -- there is no --version flag, and passing one is
# an error rather than a fallback. The binary answers `docker-agent version
# v1.141.0`, so the assertion matches $TAG and not $DOCKER_AGENT_VERSION: the
# reported string carries the `v`, and `grep -w` would refuse the bare version
# inside it because `v` is a word character. -F because a version is dots, not
# a regexp; -w so a declared 1.14.0 cannot be satisfied by an installed
# 1.141.0.
docker-agent version
docker-agent version | grep -Fw "${TAG}"
EOF

# The agent's own configuration knobs. They live here rather than in the kit's
# environment.variables because SPEC-v2 §5.5 reserved the DOCKER_ prefix for
# the sandbox runtime and kits were told not to claim it. In v3 that
# distinction disappears -- image ENV is where a workload's static environment
# belongs either way -- and so does the reason the two groups were split, which
# is why the kit's own variables now sit beside them below.
#
#   AUTO_UPDATE            -- the agent replaces its own binary when a newer
#                            release exists; the /opt layout above is what makes
#                            that possible for the non-root agent user.
#   NO_TOUR                -- skip the first-run walkthrough, which would
#                            otherwise stand between launch and a usable prompt
#                            on every fresh sandbox.
#   HIDE_TELEMETRY_BANNER  -- suppress the notice only. Telemetry itself is
#                            switched off by TELEMETRY_ENABLED=false below.
ENV DOCKER_AGENT_AUTO_UPDATE="1" \
    DOCKER_AGENT_NO_TOUR="1" \
    DOCKER_AGENT_HIDE_TELEMETRY_BANNER="1"

# v2's environment.variables, in the slot OCI already owns for static env.
# TELEMETRY_ENABLED opts out of the agent's usage reporting. The name is
# unscoped rather than vendor-prefixed, so it applies to anything else in the
# sandbox that reads it -- that direction is fail-closed, and this is the only
# knob the agent offers. Only the exact string "false" disables it.
ENV TERM="xterm-256color" \
    COLORTERM="truecolor" \
    LANG="en_US.UTF-8" \
    TELEMETRY_ENABLED="false"

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label. It stays a label in v3 -- it
# is not a capability.
LABEL com.docker.sandboxes.start-docker="true"

# The image's USER (agent, non-root) is inherited from the base rather than
# re-declared here, deliberately: the RUN block above installs as that user and
# escalates through sudo only where it must, so a re-pointed BASE_IMAGE has to
# land on a non-root `agent` user for any of it to work. sbx@1 requires the
# image config to declare a non-empty user, which an inherited USER satisfies --
# Docker carries the base's value into this image's config either way.

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier -- it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `docker-agent`.
LABEL com.docker.sandboxes.flavor="docker-agent"

# Informational only -- nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here -- nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# Where the host places the workspace under sbx@1. v2's Dockerfile declared no
# WORKDIR at all and the v2 engine mounted the workspace wherever it chose; in
# v3 the image config is what the host reads, so the kit has to state it.
WORKDIR /home/agent/workspace

# MIGRATION NOTE: v2's sandbox.entrypoint, now the image config's -- and v2's
# `CMD [ "docker-agent" ]`, which existed so a plain `docker run` got the
# agent's own defaults rather than a sandbox-shaped launch, goes away with the
# split it served. In v3 the image config is the launch contract, and a second
# spelling of it would be a second answer to one question.
#
# --yolo lets the agent run tools without asking for per-tool approval. That is
# the point of a sandbox -- the blast radius is the container.
#
# --agent-picker opens a full-screen agent chooser at launch. It requires an
# interactive terminal, which a TTY launch always provides, and it is mutually
# exclusive with the binary's own non-interactive `--exec` mode: appending
# `--exec` to this argv is an error, not an override. That is also why this kit
# declares no agent-sessions@1 prompt verb -- a verb's tail appends to this
# argv, and a one-shot run has to re-spell the whole invocation instead.
ENTRYPOINT ["docker-agent", "run", "--yolo", "--agent-picker"]
