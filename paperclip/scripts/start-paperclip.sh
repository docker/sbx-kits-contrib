#!/bin/sh
set -e
# Paperclip sandbox entrypoint. `onboard --yes` is idempotent — first run
# writes config (instance id, agent JWT secret, local secrets key) under
# PAPERCLIP_HOME and starts the server; later runs keep config and just
# start the server. The web UI and API share port 3100.
#
# Paperclip's local_trusted mode hard-requires a loopback bind, but the
# sandbox port-forwarder needs a non-loopback bind — so the kit runs in
# authenticated mode (upstream's own Docker default) with a generated,
# persisted better-auth secret. Create your account on first UI visit.

PAPERCLIP_HOME="${PAPERCLIP_HOME:-/home/agent/.paperclip}"

# Distro PostgreSQL on loopback :54329 (paperclip's embedded-postgres
# binaries can't load on the sandbox's 16KB-page arm64 kernel).
PGDATA="$PAPERCLIP_HOME/pgdata"
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | head -1)"
export PATH="$PGBIN:$PATH"
mkdir -p "$PAPERCLIP_HOME"
if [ ! -d "$PGDATA" ]; then
    initdb -D "$PGDATA" --auth=trust -U paperclip >/dev/null
fi
pg_ctl -D "$PGDATA" status >/dev/null 2>&1 || \
    pg_ctl -D "$PGDATA" -o "-p 54329 -k /tmp -h 127.0.0.1" -l "$PAPERCLIP_HOME/postgres.log" -w start >/dev/null
createdb -h 127.0.0.1 -p 54329 -U paperclip paperclip 2>/dev/null || true
export DATABASE_URL="postgresql://paperclip@127.0.0.1:54329/paperclip"

SECRET_FILE="$PAPERCLIP_HOME/better-auth-secret"
if [ ! -f "$SECRET_FILE" ]; then
    umask 077
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$SECRET_FILE"
fi
BETTER_AUTH_SECRET="$(cat "$SECRET_FILE")"
export BETTER_AUTH_SECRET

echo "Starting Paperclip (web UI on container port 3100)..." >&2
echo "Publish it to your host with: sbx ports <sandbox> --publish 3100/tcp" >&2

exec paperclipai onboard --yes
