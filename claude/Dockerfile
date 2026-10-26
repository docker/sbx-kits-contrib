# syntax=docker/dockerfile:1

# Base image for the `claude` sandbox kit.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a kind:sandbox kit names a single sandbox.image, so a second image
# would be unreachable without a second kit to consume it.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Pin a release by passing --build-arg CLAUDE_CODE_VERSION=2.1.267. The value is
# handed to the installer as its one positional target, which is the same target
# the installed binary's own `claude install [target]` takes: `stable`, `latest`,
# or a specific version. Left empty, no target is passed and the installer picks
# its own default — which is what the agent this kit replaces installs.
ARG CLAUDE_CODE_VERSION=""

# Claude Code is installed from Anthropic's own installer, which is what its
# documentation leads with and what the agent this kit replaces already used.
# npm's `@anthropic-ai/claude-code` is the alternative and is deliberately not
# taken here:
#
#   - It is the install method Claude Code then reports for itself, and the one
#     its own `claude update` / `claude install` subcommands drive. Those fetch
#     from the same release bucket this installer does, into a tree the non-root
#     `agent` user owns, so in-place self-update keeps working. An npm install
#     records a different install method and defers updates to the registry.
#   - The binary lands in ~/.local/bin, which the base image already exports on
#     PATH — as image-level ENV, so an `sbx exec` as any user resolves it. No
#     PATH edit and no symlink repair are needed, and the mixins in this
#     repository that compose onto this kit all reach `claude` through PATH.
#   - It runs no npm, so the corepack/lifecycle-script hazard does not arise.
#     That hazard is real on the npm route rather than hypothetical: the
#     published package's `bin/claude.exe` is a stub, and a `postinstall` script
#     replaces it with the platform binary selected from eight optional
#     dependencies. A corepack-managed npm shim does not run lifecycle scripts,
#     so installing through one would ship the stub and still exit 0 — the same
#     footgun the opencode kit in this repository has to disarm.
#
# `claude --version` last, deliberately: the installer's exit code says only
# that the script ran, not that a working binary reached PATH. A `curl | bash`
# whose curl dies after partial output still exits 0.
#
# The mkdir is the image half of a two-part fix for the session-state volumes
# the kit declares. When a volume mounts on a *missing* path the runtime
# auto-creates the target as root, leaving the agent user unable to write — so
# the mount-point shape has to exist in the image. That alone is not enough:
# block volumes are formatted as ext4 at create time and their root directory
# comes out owned by root whatever the image had there, which is why the kit's
# spec.yaml also carries a root-user startup chown. Doing that chown from an
# image ENTRYPOINT would not help, because the image USER is `agent`.
RUN <<EOF
set -eux

curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}

claude --version

mkdir -p \
  /home/agent/.claude/projects \
  /home/agent/.claude/sessions \
  /home/agent/.claude/todos \
  /home/agent/.claude/shell-snapshots \
  /home/agent/.claude/statsig
EOF

# Claude Code sources this file before every Bash tool call it makes, which is
# what lets an `export` the agent writes survive into the next command. The
# base image creates the file and points BASH_ENV at it; this names it for
# Claude Code specifically. Set as image ENV rather than in the kit's
# environment.variables so it travels with the image for anyone who runs it
# directly, and the CLAUDE.md the kit ships documents the same path.
ENV CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
LABEL com.docker.sandboxes.start-docker="true"

# The image's USER (agent, non-root) is inherited from the base rather than
# re-declared here, and that is on purpose too — unlike the label above, this
# one has to stay inherited: a re-pointed BASE_IMAGE must still land on a
# non-root `agent` user, or the installer in the RUN block above lands in
# /root instead of /home/agent, and every volume mount point this kit
# declares comes out root-owned instead of agent-owned.

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `claude`.
LABEL com.docker.sandboxes.flavor="claude"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# Matches the kit's entrypoint, so a plain `docker run` of this image behaves
# the way the sandbox does rather than dropping into a permission prompt nobody
# can answer.
CMD [ "claude", "--dangerously-skip-permissions" ]
