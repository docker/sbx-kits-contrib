# syntax=docker/dockerfile:1
# The overlay: docker-agent landing on any base.
#
# Unlike the sibling agent mixins in this repo, nothing here has to be worked
# around: Docker Agent ships one static binary per platform as a release asset,
# so the build downloads it straight into the staging tree and the overlay is a
# genuine relocation rather than a copy-out from an unrelocatable installer.
# The workload's own base is still the build stage, because the release-tag
# resolution below wants curl and a CA store.
#
# The /opt tree is agent-owned (uid/gid 1000) because DOCKER_AGENT_AUTO_UPDATE
# means the agent user replaces the binary in place; a root-owned home would
# fail every self-update in this shape. That is also why the mixin needs no
# install hook where the workload has one -- the layout arrives correct in the
# layer instead of being re-established at create.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Docker Agent publishes one static binary per platform, so the release asset
# name has to be selected at build time. TARGETARCH is supplied by BuildKit and
# is the only correct source for it -- deriving it from `uname -m` would read
# the builder, not the target, and silently produce an amd64 binary in an arm64
# overlay under emulation.
ARG TARGETARCH

# Supplied by the descriptor's `version` arg, which declares the same empty
# default. Left empty, the build resolves the newest release from github.com's
# /releases/latest redirect, not the releases API: unauthenticated
# api.github.com quota is counted per source IP and hosted CI runners share
# egress addresses, so the API can rate-limit the fetch mid-build.
ARG DOCKER_AGENT_VERSION=""

# Root for the staging tree's ownership work; nothing from this stage ships
# except /out, so the build user is not the sandbox's.
USER root

# `test -x` at the end because a completed RUN proves an exit code, not an
# installed binary: curl's own failure modes and a truncated asset both need to
# fail the build here rather than ship an overlay with no agent in it.
RUN <<EOF
set -euxo pipefail

TAG="${DOCKER_AGENT_VERSION}"
if [ -z "${TAG}" ]; then
    TAG=$(curl -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/docker/docker-agent/releases/latest" | sed -n 's#.*/releases/tag/##p') || TAG=""
fi
if [ -z "${TAG}" ]; then
    echo "Failed to resolve a docker-agent release tag: DOCKER_AGENT_VERSION is empty and the request to github.com/docker/docker-agent/releases/latest failed or did not redirect to a release tag (curl's own error, if any, is printed above). Supply the kit's version arg, or --build-arg DOCKER_AGENT_VERSION=<tag>." >&2
    exit 1
fi

mkdir -p /out/opt/docker-agent/bin /out/usr/local/bin /out/etc/profile.d

curl -fsSL "https://github.com/docker/docker-agent/releases/download/${TAG}/docker-agent-linux-${TARGETARCH}" \
    -o /out/opt/docker-agent/bin/docker-agent
chmod 0755 /out/opt/docker-agent/bin/docker-agent
chown -R 1000:1000 /out/opt/docker-agent

# Relative to the composed root, not to /out: the link is resolved inside the
# sandbox, where the staging prefix does not exist.
ln -s /opt/docker-agent/bin/docker-agent /out/usr/local/bin/docker-agent

test -x /out/opt/docker-agent/bin/docker-agent
EOF

# v2's environment.variables plus the agent's own knobs, which the v2 Dockerfile
# set as image ENV. A mixin's image config is not the composed image's, so
# static env rides the overlay as a profile script instead.
#
#   AUTO_UPDATE            -- the agent replaces its own binary when a newer
#                            release exists; the agent-owned /opt layout above
#                            is what makes that possible.
#   NO_TOUR                -- skip the first-run walkthrough.
#   HIDE_TELEMETRY_BANNER  -- suppress the notice only; telemetry itself is off
#                            via TELEMETRY_ENABLED=false.
RUN printf 'export TERM=xterm-256color\nexport COLORTERM=truecolor\nexport LANG=en_US.UTF-8\nexport TELEMETRY_ENABLED=false\nexport DOCKER_AGENT_AUTO_UPDATE=1\nexport DOCKER_AGENT_NO_TOUR=1\nexport DOCKER_AGENT_HIDE_TELEMETRY_BANNER=1\n' \
      > /out/etc/profile.d/docker-agent-env.sh

# No com.docker.sandboxes.start-docker label here, deliberately. The workload
# sets it because it owns a base that carries a Docker engine; setting it from
# an overlay would ask the runtime to start Docker mode over whatever base the
# user composed, which yields a sandbox in Docker mode with nothing to run when
# that base has no engine. A base that wants it declares it.
FROM scratch
COPY --from=build /out /
