# syntax=docker/dockerfile:1
# PROTOTYPE. Ships the sqlite3 shell the install hook needs to write kiro-cli's
# placeholder sign-in. The kiro workload has no SQLite tool of its own.
#
# Installed over the workload's own base and copied out alone: sqlite3 links
# libsqlite3, readline and zlib, which that base already carries at the same
# versions, so the overlay ships one binary under its own prefix and nothing
# that could shadow the base's libraries.
ARG BASE_IMAGE=docker.io/sbx/kiro:latest
FROM ${BASE_IMAGE} AS build

USER root

# The guard fails the build if installing sqlite3 changes any other package:
# the copied binary would then need a library version the base lacks.
RUN set -eux; \
    before="$(dpkg-query -W | awk '$1 !~ /^sqlite3(:|$)/')"; \
    apt-get update; \
    apt-get install -y --no-install-recommends sqlite3; \
    after="$(dpkg-query -W | awk '$1 !~ /^sqlite3(:|$)/')"; \
    [ "$after" = "$before" ] || { echo "installing sqlite3 changed packages the base provides" >&2; exit 1; }; \
    mkdir -p /out/opt/kiro-host-auth/bin; \
    cp /usr/bin/sqlite3 /out/opt/kiro-host-auth/bin/sqlite3; \
    chown -R 0:0 /out/opt; \
    /out/opt/kiro-host-auth/bin/sqlite3 --version

FROM scratch
COPY --from=build /out /
