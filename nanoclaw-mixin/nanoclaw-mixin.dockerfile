# syntax=docker/dockerfile:1
# NanoClaw as an overlay.
#
# The workload's content is a published third-party image rather than an
# install this repo drives, so there is no install to relocate and no build
# stage that could reproduce one: the image IS the distribution. The overlay
# therefore copies out of it -- the shape the devin mixin uses for the same
# reason -- and copies exactly the paths this kit's own declarations name:
# the entrypoint script v2 pointed `sandbox.entrypoint` at, and the NanoClaw
# checkout the kit's README sends users into with `sbx exec -w`.
#
# What this overlay cannot carry is everything else that image installs into
# its rootfs -- the Node runtime NanoClaw runs under, the OneCLI and Postgres
# clients, the system packages its setup expects. Copying a third-party
# image's whole filesystem into an overlay would not be an overlay; it would
# shadow the base workload wholesale. So this composes onto a base that
# already carries an equivalent runtime, and the workload kit (../nanoclaw)
# stays the supported way to run the agent standalone.
FROM docker.io/nanoco/nanoclaw:sbx-claude-alpha AS src

# Staged into /out rather than copied into the overlay with `COPY --chown`:
# BuildKit applies that flag to every parent it creates, so copying straight to
# /home/agent/nanoclaw would ship /home itself owned by the agent, and an
# overlay's directory entries override the base's. The chown starts at
# /out/home/agent so /home stays root's and $HOME stays the agent's.
USER root
RUN mkdir -p /out/home/agent /out/usr/local/bin \
 && cp -a /usr/local/bin/nanoclaw-start /out/usr/local/bin/nanoclaw-start \
 && cp -a /home/agent/nanoclaw /out/home/agent/nanoclaw \
 && chown -R 1000:1000 /out/home/agent

# The overlay: the host launcher and the checkout, landing on any base.
FROM scratch
COPY --from=src /out /

# v2's environment.variables. A mixin's image config is not the composed
# image's, so what the workload sets with ENV rides a profile.d snippet the
# base's login shell sources instead. NO_PROXY and no_proxy are both exported,
# as v2 set both: the tooling inside reads whichever spelling it was written
# against.
COPY <<'EOF' /etc/profile.d/nanoclaw-env.sh
export IS_SANDBOX=1
export NANOCLAW_AGENT_PROVIDER=claude
export NANOCLAW_NO_DIAGNOSTICS=1
export NODE_NO_WARNINGS=1
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
export ONECLI_BIND_HOST=0.0.0.0
export ONECLI_GATEWAY_URL=http://127.0.0.1:10255
export ONECLI_URL=http://127.0.0.1:10254
export TZ=UTC
EOF
