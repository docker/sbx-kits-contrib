# syntax=docker/dockerfile:1
# The overlay: the Devin CLI and its auth wrapper landing on any base.
#
# Cognition's install.sh is a per-user installer with no --prefix and a
# manifest it resolves itself, so there is nothing to point at a staging
# directory. This therefore does not try: it takes the workload's own base as a
# build stage, runs the *unmodified* install -- same `|| true` around the
# TTY-less `devin setup`, same `devin --version` gate, same devin-cli rename --
# and copies the resulting tree into a scratch overlay at exactly the path it
# was built for.
#
# The copy is the whole of /home/agent/.local: the installer's layout is a
# version directory plus a "current" symlink plus launchers in bin, and the
# devin-cli link created below deliberately points at the symlink TARGET so
# `devin update` keeps moving it. Copying only bin would land three dangling
# links.
#
# devin-entrypoint.sh is a copy of the workload kit's wrapper, unavoidably: a
# kit directory is its own build context, so an overlay cannot COPY out of a
# sibling kit's. It must stay byte-identical to ../devin/devin-entrypoint.sh.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Runs as the base image's default user (`agent`, uid 1000), which matters:
# install.sh is a per-user installer, so everything lands under /home/agent
# owned by the user that will run it.
RUN <<EOF
set -eux

# `|| true` is not laziness. install.sh ends by running `devin setup`, an
# interactive wizard that cannot complete without a TTY and exits non-zero
# ("Login canceled"). Because that is the script's last command it is also the
# script's exit status, so a clean install reports failure here.
curl -fsSL https://cli.devin.ai/install.sh | bash || true

# ...so assert the outcome instead of trusting the status that was just
# discarded. A genuine download, checksum or unpack failure still fails the
# build here, which is the only thing that makes the `|| true` above safe.
devin --version

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

# The launcher a composed sandbox resolves as `devin`: it checks authentication
# state, drops into Devin's manual token flow when there is none, replaces any
# real key left on disk with the proxy's placeholder, and only then hands off
# to devin-cli.
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
