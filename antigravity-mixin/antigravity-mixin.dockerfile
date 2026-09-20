# syntax=docker/dockerfile:1
# The overlay: agy landing on any base.
#
# Google's install.sh is a per-user installer that resolves its target from a
# manifest it fetches itself, so there is nothing to point at a staging prefix
# and no supported way to make what it writes relocatable. This therefore does
# not try: it takes the workload's own base as a build stage, runs the
# *unmodified* install -- same --dir, same build-time `agy --help` gate -- and
# copies the paths it produced into a scratch overlay at exactly the paths they
# were built for.
#
# The copy is the whole of /home/agent/.local rather than just .local/bin:
# --dir names where the launcher goes, not where the installer stages the
# bundle it launches, so copying bin alone risks an overlay of launchers with
# nothing behind them. The per-user prefix is the smallest boundary that is
# certain to contain both.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER agent
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-antigravity.sh && \
    bash /tmp/install-antigravity.sh --dir /home/agent/.local/bin && \
    rm -f /tmp/install-antigravity.sh && \
    agy --help >/dev/null

# v2's environment.variables. A mixin's image config is not the composed
# image's, so static env rides the overlay as a profile script instead of ENV.
USER root
RUN mkdir -p /out/etc/profile.d && \
    printf 'export BROWSER=xdg-open\n' > /out/etc/profile.d/antigravity-env.sh

# No com.docker.sandboxes.start-docker label here, deliberately. The workload
# sets it because it owns a base that carries a Docker engine; setting it from
# an overlay would ask the runtime to start Docker mode over whatever base the
# user composed, which yields a sandbox in Docker mode with nothing to run when
# that base has no engine. A base that wants it declares it.
# The install tree is staged into /out rather than copied into the overlay with
# `COPY --chown`: BuildKit applies that flag to every parent it creates, so
# copying to /home/agent/.local would ship /home itself owned by the agent, and
# an overlay's directory entries override the base's. Numeric ownership because
# scratch carries no /etc/passwd for a name to resolve against; 1000:1000 is
# the platform floor's `agent` user. /out/home stays root's.
RUN mkdir -p /out/home/agent \
 && cp -a /home/agent/.local /out/home/agent/.local \
 && chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=build /out /
