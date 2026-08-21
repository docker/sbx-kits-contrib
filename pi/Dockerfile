# syntax=docker/dockerfile:1.7
# Pi sandbox image.
#
# pi is pre-baked so sandbox creation is fast: the kit used to npm-install it
# at create time, which put a multi-minute download in front of every new
# sandbox. The kit (spec.yaml) now only applies policy and names `pi` as the
# entrypoint.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# openclaw/kiro/copilot.

FROM docker/sandbox-templates:shell-docker

# Upstream releases frequently. Bump deliberately, and keep this in step with
# the version named in README.md.
ARG PI_VERSION=0.84.2

USER root
# No Node install step: the template already ships Node 22.22.1, which
# satisfies pi's `engines.node >= 22.19.0`. (openclaw's image has to run
# `n 22` because openclaw needs a newer minor than the template had at the
# time -- pi does not.)
#
# chown afterwards because the global prefix is agent-owned in the template
# and a root install would leave it root-owned: `pi update --self` and
# `pi install` run as agent inside the sandbox and would then fail on EACCES.
# The kit's old create-time install ran as uid 1000 for the same reason.
RUN npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}" && \
    chown -R agent:agent "$(npm prefix -g)"

# The global bin dir is on PATH in this image, but not in every context that
# may invoke the binary (startup commands and some exec paths run with a
# minimal PATH). A symlink somewhere always on PATH costs nothing.
RUN ln -sf "$(npm prefix -g)/bin/pi" /usr/local/bin/pi

USER agent
WORKDIR /home/agent
CMD ["pi"]
