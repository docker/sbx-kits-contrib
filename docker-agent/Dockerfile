# syntax=docker/dockerfile:1

# Base image for the `docker-agent` sandbox kit.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a kind:sandbox kit names a single sandbox.image, so a second image
# would be unreachable without a second kit to consume it.
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
# is the only correct source for it — deriving it from `uname -m` would read the
# builder, not the target, and silently produce an amd64 binary in an arm64
# image under emulation.
ARG TARGETARCH

# Pin a release by passing --build-arg DOCKER_AGENT_VERSION=<tag>. Left empty,
# the build resolves the newest release from github.com's /releases/latest
# redirect, not the releases API: unauthenticated api.github.com quota is
# counted per source IP and hosted CI runners share egress addresses, so the
# API can rate-limit the fetch mid-build. The redirect resolves the newest
# release, skipping drafts and pre-releases.
ARG DOCKER_AGENT_VERSION=""

# The agent self-updates in place (DOCKER_AGENT_AUTO_UPDATE below), which means
# rewriting its own binary, which it can only do where the agent user can write.
# So the binary lives under an agent-owned /opt path and /usr/local/bin carries
# a symlink for PATH lookups. Installing straight into /usr/local/bin — where
# only root can write — would leave self-update failing at run time.
#
# `test -x` at the end because a completed RUN proves an exit code, not an
# installed binary: curl's own failure modes and a truncated asset both need to
# fail the build here rather than ship an image with no agent in it.
RUN <<EOF
set -euxo pipefail

TAG="${DOCKER_AGENT_VERSION}"
if [ -z "${TAG}" ]; then
    TAG=$(curl -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/docker/docker-agent/releases/latest" | sed -n 's#.*/releases/tag/##p') || TAG=""
fi
if [ -z "${TAG}" ]; then
    echo "Failed to resolve a docker-agent release tag: DOCKER_AGENT_VERSION is empty and the request to github.com/docker/docker-agent/releases/latest failed or did not redirect to a release tag (curl's own error, if any, is printed above). Pass --build-arg DOCKER_AGENT_VERSION=<tag>." >&2
    exit 1
fi

sudo install -d -o agent -g agent /opt/docker-agent/bin
curl -fsSL "https://github.com/docker/docker-agent/releases/download/${TAG}/docker-agent-linux-${TARGETARCH}" \
    -o /opt/docker-agent/bin/docker-agent
chmod 0755 /opt/docker-agent/bin/docker-agent
sudo ln -sf /opt/docker-agent/bin/docker-agent /usr/local/bin/docker-agent

test -x /opt/docker-agent/bin/docker-agent
EOF

# The agent's own configuration knobs. They live here rather than in the kit's
# environment.variables because SPEC-v2 §5.5 reserves the DOCKER_ prefix for the
# sandbox runtime and kits are told not to claim it. Image ENV reaches the
# container environment the same way and stays overridable per sandbox.
#
#   AUTO_UPDATE            — the agent replaces its own binary when a newer
#                            release exists; the /opt layout above is what makes
#                            that possible for the non-root agent user.
#   NO_TOUR                — skip the first-run walkthrough, which would
#                            otherwise stand between launch and a usable prompt
#                            on every fresh sandbox.
#   HIDE_TELEMETRY_BANNER  — suppress the notice only. Telemetry itself is
#                            switched off by the kit's TELEMETRY_ENABLED=false.
ENV DOCKER_AGENT_AUTO_UPDATE="1" \
    DOCKER_AGENT_NO_TOUR="1" \
    DOCKER_AGENT_HIDE_TELEMETRY_BANNER="1"

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `docker-agent`.
LABEL com.docker.sandboxes.flavor="docker-agent"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# Bare `docker-agent`, no subcommand and no flags: the kit's entrypoint supplies
# `run --yolo --agent-picker`, so a plain `docker run` of this image gets the
# agent's own defaults — its help output, and its per-tool approval prompts —
# rather than a sandbox-shaped launch.
CMD [ "docker-agent" ]
