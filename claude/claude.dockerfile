# syntax=docker/dockerfile:1

# Content recipe for the `claude` workload kit.
#
# MIGRATION NOTE: in v2 this Dockerfile built a separate base image
# (`docker.io/sbx/claude-image:latest`) that spec.yaml then named in
# `sandbox.image`. A v3 workload's layers ARE the root filesystem, so the two
# artifacts collapse into one: this recipe is the kit's content, and there is no
# second image reference to keep in sync.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a workload kit is a single root filesystem, so a second image would
# be unreachable without a second kit to consume it.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Pin a release with the kit's `version` arg, which the descriptor hands over as
# this build arg. The value is passed to the installer as its one positional
# target, which is the same target the installed binary's own
# `claude install [target]` takes: `stable`, `latest`, or a specific version.
# Left empty — the arg's default — no target is passed and the installer picks
# its own default, which is what the agent this kit replaces installs.
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
# lifecycle capability also carries a root-user startup chown. Doing that chown
# from an image ENTRYPOINT would not help, because the image USER is `agent`.
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
# Claude Code specifically. It was already image ENV in v2 rather than a kit
# environment variable, so it travels with the image for anyone who runs it
# directly, and the CLAUDE.md the kit ships documents the same path.
ENV CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh

# MIGRATION NOTE: v2's `environment.variables`, in the slot OCI already owns for
# static env. v3 carries no static-env grammar — a workload's image config is
# the composed image's config, so ENV is where these belong.
#
# IS_SANDBOX marks the environment for tools that check it.
#
# DISABLE_TELEMETRY opts out of usage reporting. The agent reports by default
# and the built-in this kit is extracted from left it that way — this is a
# deliberate deviation, taken because every other agent kit in this repo that
# has a switch to throw throws it, and because the variable is fail-closed: it
# can only turn reporting off, never on. Override it per sandbox to get the
# default behaviour back.
#
# Verified against the shipped binary, whose consent ladder reads
# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC > DISABLE_TELEMETRY > DO_NOT_TRACK.
# The first of those is NOT used here even though it is the broadest: it puts
# the agent into an "essential traffic only" mode that also takes away
# /feedback, Projects and DesignSync, which is a feature cut rather than a
# telemetry decision. DO_NOT_TRACK is skipped for the opposite reason — it is
# the cross-tool convention and would silence every other tool in the sandbox
# as well, which is not this kit's call to make on the user's behalf.
#
# DISABLE_ERROR_REPORTING covers crash reporting, which the variable above does
# not — the binary gates the two independently. Same reasoning, same
# fail-closed direction.
ENV IS_SANDBOX=1
ENV DISABLE_TELEMETRY=1
ENV DISABLE_ERROR_REPORTING=1

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# It stays a LABEL rather than becoming a capability: v3 has no type for it, and
# `privileged@1` is a different and much broader ask than this kit ever made.
LABEL com.docker.sandboxes.start-docker="true"

# The image's USER (agent, non-root) is inherited from the base rather than
# re-declared here, and that is on purpose too — unlike the label above, this
# one has to stay inherited: a re-pointed BASE_IMAGE must still land on a
# non-root `agent` user, or the installer in the RUN block above lands in
# /root instead of /home/agent, and every volume mount point this kit
# declares comes out root-owned instead of agent-owned.
#
# The inherited value is also what satisfies the kit's sbx@1 declaration, which
# requires the image config to name a user the host can resolve to a uid, gid
# and home. WORKDIR is inherited for the same reason: sbx@1 places the
# workspace at the image's working directory.

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

# MIGRATION NOTE: v2's `sandbox.entrypoint`, moved into the image config — in v3
# the image carries the runtime contract and the descriptor duplicates none of
# it. This replaces the v2 recipe's CMD, which existed only so a plain
# `docker run` matched the kit's entrypoint; stated as ENTRYPOINT it is now the
# same single declaration for both.
#
# Claude Code's own permission prompts are redundant here — the container IS the
# sandbox, and a prompt nobody can answer just deadlocks the session. The
# settings.json written by the install hook says the same thing in config form
# (permissions.defaultMode plus the two acceptance flags); both are kept so
# neither surface has to be the only line of defence.
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
