# syntax=docker/dockerfile:1
# Same pinned installation recipe as the devin-mixin kit.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Supplied by the descriptor's `version` arg, which owns the default and the
# accepted shape. No default here on purpose: an unset value must fail the
# build rather than quietly fall back to whatever "current" means today,
# because the descriptor expands this same value into a versioned provide.
#
# Cognition's installer reads no version from its environment or its argv --
# the top-level script carries a bare `PINNED_VERSION=""` literal, so a
# DEVIN_VERSION passed *to* it would be ignored. The pin is expressed by WHICH
# script is fetched instead; see the RUN below.
ARG DEVIN_VERSION

# Runs as the base image's default user (`agent`, uid 1000), which matters:
# setup.sh is a per-user installer, so everything lands under /home/agent
# owned by the user that will run it.
RUN <<EOF
set -eux

test -n "${DEVIN_VERSION}" || { echo "DEVIN_VERSION is empty; pass the kit's version arg" >&2; exit 1; }

# `|| true` is not laziness. setup.sh ends by running `devin setup`, an
# interactive wizard that cannot complete without a TTY and exits non-zero
# ("Login canceled"). Because that is the script's last command it is also the
# script's exit status, so a clean install reports failure here.
#
# The versioned script, not the top-level https://cli.devin.ai/install.sh: the
# two are byte-identical apart from `PINNED_VERSION`, which the top-level one
# leaves empty so the manifest lookup lands on `current/`. Fetching this path
# is what makes the install pinned. The host is static.devin.ai, the
# installer's own BASE_URL -- cli.devin.ai serves only the top-level script and
# 301s a versioned path to the docs site.
curl -fsSL "https://static.devin.ai/cli/${DEVIN_VERSION}/setup.sh" | bash || true

# ...so assert the outcome instead of trusting the status that was just
# discarded. A genuine download, checksum or unpack failure still fails the
# build here, which is the only thing that makes the `|| true` above safe.
#
# `grep -Fw` rather than a bare run, because the descriptor publishes
# `devin@${DEVIN_VERSION}` as a provide: a pin that silently installed some
# other release would make that claim false, and this is the line that stops
# it. -F because a version is dots, not a regexp; -w so a declared 3000.10.3
# cannot be satisfied by an installed 3000.10.31.
devin --version
devin --version | grep -Fw "${DEVIN_VERSION}"

# The installer's `devin` is the only one on PATH, and the auth wrapper has to
# take that name so a composed sandbox's `devin` is the wrapper. Expose the
# real CLI as `devin-cli` first.
#
# `readlink` without -f on purpose: it copies the symlink's TARGET rather than
# resolving it all the way to today's version directory, so `devin-cli` keeps
# following the installer's own "current" pointer. devin update moves that
# pointer, so devin-cli follows it.
ln -s "$(readlink /home/agent/.local/bin/devin)" /home/agent/.local/bin/devin-cli

# Remove the installer's symlink before the COPY below replaces it. Without
# this, COPY resolves the existing symlink and writes the wrapper THROUGH it,
# overwriting the real CLI binary inside the version directory -- and the
# wrapper would then exec itself.
rm /home/agent/.local/bin/devin
EOF

# Same wrapper as the workload; keep these copies byte-identical. Each kit
# directory is its own build context, so neither can COPY a sibling's script.
COPY --chown=agent:agent --chmod=0755 devin-entrypoint.sh /home/agent/.local/bin/devin

# No com.docker.sandboxes.start-docker label here, deliberately. The workload
# sets it because it owns a base that carries a Docker engine; setting it from
# an overlay would ask the runtime to start Docker mode over whatever base the
# user composed, which yields a sandbox in Docker mode with nothing to run when
# that base has no engine. A base that wants it declares it.
#
# v2 declared no environment.variables either, so there is no /etc/profile.d
# script in this overlay -- nothing to export.
# The install tree is staged into /out rather than copied into the overlay with
# `COPY --chown`: BuildKit applies that flag to every parent it creates, so
# copying to /home/agent/.local would ship /home itself owned by the agent, and
# an overlay's directory entries override the base's. Numeric ownership because
# scratch carries no /etc/passwd for a name to resolve against; 1000:1000 is
# the platform floor's `agent` user. /out/home stays root's.
#
# Root for the staging step only — everything above deliberately runs as the
# base's `agent` user, and /out cannot be created under a root-owned /.
USER root
RUN mkdir -p /out/home/agent \
 && cp -a /home/agent/.local /out/home/agent/.local \
 && chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=build /out /
