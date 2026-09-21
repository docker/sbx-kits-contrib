# syntax=docker/dockerfile:1

# Content recipe for the `copilot` workload kit — the v2 Dockerfile, renamed to
# the companion stem the v3 frontend looks for (copilot.yaml ->
# copilot.dockerfile) and grown the one stanza that used to live in spec.yaml:
# v2's `sandbox.entrypoint`. A v3 workload's layers are the root filesystem and
# its image config is the runtime contract, so the descriptor declares neither.
# (v2 declared no `environment.variables` for this kit, so there is no ENV to
# carry across.)
#
# v2's `sandbox.image: docker.io/sbx/copilot-image:latest` named the image CI
# built from this file and published separately. In v3 there is one artifact:
# this recipe's output *is* the kit, so the reference is gone rather than moved.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Copilot CLI has no interactive-auth wrapper to install (unlike kiro's
# device-flow launcher) — it reads GH_TOKEN from the environment, injected by
# the sandbox proxy per the descriptor's credential entries. So this is just the
# upstream install script.
#
# The install is pinned, via the kit's `version` arg. VERSION is the
# installer's own knob for this, documented in its usage header ("Export
# PREFIX ..."-style options) and read where it picks the download URL: a
# specific value selects
# `.../releases/download/v<version>/copilot-<platform>-<arch>.tar.gz`, and the
# installer adds the `v` itself, so the arg carries the bare number SPEC-v3
# §5.2 requires.
#
# No default on the ARG, deliberately. An empty VERSION is not "no opinion" to
# this installer — its first branch is `[ "${VERSION}" = "latest" ] || [ -z
# "$VERSION" ]`, so empty means latest. A float underneath a descriptor
# publishing `copilot@${{ kit.args.version }}` is the one failure mode worse
# than floating outright, so a missing value fails the build.
#
# The installed binary is asked for its version and the answer compared
# against the pin: the installer's exit code says only that the script ran.
# `copilot --version` prints "GitHub Copilot CLI <version>." on its first line
# — trailing full stop included, and a second line advertising `copilot
# update` — so the last field of the first line, minus that period, is the
# number to match.
ARG COPILOT_VERSION
RUN <<EOF
set -exo pipefail
[ -n "${COPILOT_VERSION}" ] || { echo "COPILOT_VERSION must be set" >&2; exit 1; }

export VERSION="${COPILOT_VERSION}"
curl -fsSL https://gh.io/copilot-install | bash

installed=$(copilot --version | head -n1 | awk '{print $NF}' | sed 's/\.$//')
[ "$installed" = "${COPILOT_VERSION}" ] || {
  echo "installed copilot $installed != pinned ${COPILOT_VERSION}" >&2; exit 1; }
EOF

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# It stays a label rather than becoming a capability: v3 has no
# Docker-in-Docker capability type, and inventing one would be a declaration no
# runtime answers.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `copilot`.
LABEL com.docker.sandboxes.flavor="copilot"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# v2's sandbox.entrypoint. --yolo makes Copilot CLI run tools without asking for
# per-tool approval, which is the point of a sandbox: the blast radius is the
# container, and an approval prompt nobody can answer just deadlocks a
# non-interactive session.
#
# MIGRATION NOTE: this replaces v2's `CMD ["copilot"]`. That CMD existed so a
# bare `docker run` of the separately-published base image started the agent
# without --yolo; now that the descriptor's launch command lives in the image
# config, a surviving CMD would be appended to this argv as a stray `copilot`
# argument.
ENTRYPOINT ["copilot", "--yolo"]
