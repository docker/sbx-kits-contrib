# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
#
# (SIEM_COLLECTOR_AUTH_ID is Cortex XSIAM's numeric HTTP-collector key ID - a
# non-secret, carried as the siemCollectorAuthId kit arg and rendered into the
# config. The linter rule keys on the "AUTH" substring and cannot know that, so
# we skip it rather than let a known-safe value trip every build. The actual
# collector token is never an ARG/ENV here - it is a proxy-injected placeholder.)
#
# Overlay recipe for the PANW SIEM telemetry mixin.
#
# MIGRATION NOTE: in v2 the Fluent Bit config lived under files/ on disk and was
# staged into the sandbox with the `${{ kit.args.* }}` placeholders expanded at
# spec-decode time. In v3 that pure content becomes an overlay layer: the three
# config files are rendered here with the build-arg values and baked under
# /home/agent/.config/fluent-bit. The Fluent Bit INSTALL does NOT move here - it
# branches on the runtime page size and runs apt in a mixin, so it stays a
# create-time lifecycle hook in panw-siem-telemetry.yaml.
#
# The overlay lands on any base agent workload; the create-time install hook
# puts the fluent-bit binary in place and the startup hook runs the forwarder.

ARG SIEM_COLLECTOR_HOST=siem-collector.example.com
ARG SIEM_COLLECTOR_PATH=/logs/v1/event
ARG SIEM_COLLECTOR_AUTH_ID=

# Render stage: substitute the kit-arg placeholders into the config files. The
# sed replaces ONLY the `${{ kit.args.* }}` tokens; runtime `${VAR}` shell and
# Fluent Bit variables (SIEM_COLLECTOR_TOKEN, HOSTNAME) are a different syntax
# and pass through untouched - which is the whole point of the `${{` opener.
# Nothing from this stage ships except /out.
FROM debian:bookworm-slim AS render
ARG SIEM_COLLECTOR_HOST
ARG SIEM_COLLECTOR_PATH
ARG SIEM_COLLECTOR_AUTH_ID
COPY files/home/.config/fluent-bit/ /src/
RUN set -eu; \
    dst=/out/home/agent/.config/fluent-bit; \
    mkdir -p "$dst"; \
    for f in parsers.conf sandbox-telemetry.conf run-telemetry.sh; do \
      sed \
        -e "s|\${{ kit.args.siemCollectorHost }}|${SIEM_COLLECTOR_HOST}|g" \
        -e "s|\${{ kit.args.siemCollectorPath }}|${SIEM_COLLECTOR_PATH}|g" \
        -e "s|\${{ kit.args.siemCollectorAuthId }}|${SIEM_COLLECTOR_AUTH_ID}|g" \
        "/src/$f" > "$dst/$f"; \
    done; \
    chmod 0644 "$dst"/*.conf; \
    chmod 0755 "$dst/run-telemetry.sh"; \
    # Overlay ownership invariants: /home owned by root (0:0), /home/agent and
    # everything under it owned by the agent user (uid 1000).
    chown -R 0:0 /out/home; \
    chown -R 1000:1000 /out/home/agent

# The overlay: a scratch root carrying only the rendered Fluent Bit config.
FROM scratch
COPY --from=render /out /
