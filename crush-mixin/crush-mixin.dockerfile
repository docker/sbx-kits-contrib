# syntax=docker/dockerfile:1
# The overlay: crush landing on any base.
#
# An apt install is the case where relocation is not available at all. Crush
# comes from Charm's apt repository, and `apt-get install --root=/out` is not a
# supported shape for a third-party repo (it wants its own dpkg database, its
# own keyring trust and a bootstrapped base under the target root); dpkg's
# --instdir has the same problem and additionally rewrites maintainer-script
# assumptions. So this does not fight it: the workload's own base becomes a
# build stage, the *unmodified* apt install runs there, and the overlay carries
# out exactly the paths that install produced.
#
# Which paths those are is read from the package rather than guessed -- Charm
# can move a binary between /usr/bin and /usr/local/bin without telling this
# file, and `dpkg -L` is the record that cannot be wrong. tar carries the
# entries across so modes, symlinks and ownership survive the move.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

# Cache invalidation, exactly as in the workload: BuildKit re-fetches the URL
# on every build to compute its digest, so this layer and every RUN after it
# re-run whenever upstream cuts a release -- and upstream re-cuts a rolling
# `nightly` entry every night, so the digest moves daily regardless. Unlike the
# workload, the 150 KB feed never ships: it lands in this build stage only, and
# the overlay below carries nothing but the package's own files.
ADD --chmod=644 https://github.com/charmbracelet/crush/releases.atom /tmp/crush-releases.atom

# Charm's GPG key, apt repository and install, run unmodified. repo.charm.sh
# and the Gemfury-fronted S3 bucket its index redirects package downloads to
# are build-time-only: neither is a credential inject domain, so neither
# belongs in the kit's runtime allow list.
USER root
RUN set -euo pipefail; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg; \
    echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
      > /etc/apt/sources.list.d/charm.list; \
    apt-get update -qq; \
    apt-get install -y -qq crush; \
    rm -rf /var/lib/apt/lists/*

# The build-time gate, as in the workload: this runs the installed binary, so
# a release apt cannot install, or whose binary fails to start, fails the build
# instead of shipping an overlay with a non-starting agent in it.
RUN crush --version

# Copy the package's own files out, and nothing else. Directories are dropped
# (extraction recreates the ones it needs) and the final `test -x` proves the
# executable actually landed at the path the build stage resolves it at, so a
# packaging change that moved it fails here rather than producing a silently
# empty overlay.
RUN set -eu; \
    mkdir -p /out; \
    dpkg -L crush | while IFS= read -r p; do \
        if [ -d "$p" ]; then continue; fi; \
        if [ -e "$p" ] || [ -L "$p" ]; then printf '%s\n' "${p#/}"; fi; \
    done > /tmp/crush.files; \
    tar -C / -cf - --no-recursion -T /tmp/crush.files | tar -C /out -xf -; \
    rm -f /tmp/crush.files; \
    test -x "/out$(command -v crush)"

# v2 declared no environment.variables, so there is no /etc/profile.d script
# here -- nothing to export.
FROM scratch
COPY --from=build /out /
