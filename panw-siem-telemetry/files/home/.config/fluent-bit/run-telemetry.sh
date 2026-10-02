#!/bin/sh
# Launch the Fluent Bit telemetry forwarder with auth headers built at runtime.
#
# Fluent Bit renders `Header Key <empty>` as `Key: Key`, so we cannot leave the
# Authorization / x-xdr-auth-id values empty in the static conf. Instead we copy
# the base conf and append each Header line only when its value is non-empty.
# [OUTPUT] is the last section in the base conf, so appended `Header` lines
# attach to it.
set -eu

CONF_DIR=/home/agent/.config/fluent-bit
BASE="$CONF_DIR/sandbox-telemetry.conf"
RT=/home/agent/.sandbox/telemetry-runtime.conf

mkdir -p /home/agent/.sandbox/logs
cp "$BASE" "$RT"

# Authorization: emit only when a token (placeholder or real) is present. Write
# the literal ${SIEM_COLLECTOR_TOKEN} so Fluent Bit expands it - the proxy then
# swaps the placeholder for the real token on the wire.
if [ -n "${SIEM_COLLECTOR_TOKEN:-}" ]; then
    printf '    Header Authorization ${SIEM_COLLECTOR_TOKEN}\n' >> "$RT"
fi

# x-xdr-auth-id: Cortex XSIAM's non-secret numeric key ID. Substituted from the
# kit arg at spec-decode time; emit the header only when it is set.
AUTH_ID='${{ kit.args.siemCollectorAuthId }}'
if [ -n "$AUTH_ID" ]; then
    printf '    Header x-xdr-auth-id %s\n' "$AUTH_ID" >> "$RT"
fi

FLB="$(command -v fluent-bit || echo /opt/fluent-bit/bin/fluent-bit)"
exec "$FLB" -c "$RT"
