# syntax=docker/dockerfile:1

# Overlay recipe for the claude mixin: the same install the `claude` workload
# performs, landed under /out and shipped as a delta that composes onto any base.
#
# Why a build stage over the workload's own base rather than a relocatable
# `--prefix` install: Anthropic's installer is not relocatable. It writes a
# versioned tree under ~/.local/share/claude and wires ~/.local/bin/claude at it,
# and the workload kit's recipe documents at length why this repo installs that
# way rather than from npm — the install method is what `claude update` and
# `claude install` drive, into a tree the non-root agent user owns, so in-place
# self-update keeps working. Changing the install method for the mixin shape
# would change that behavior. So the unmodified install runs over the workload's
# base, and only the paths it produced are staged into the overlay.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

ARG CLAUDE_CODE_VERSION=""

# Run as the base's own non-root `agent` user (inherited USER), which is what
# puts the install in /home/agent/.local rather than /root. `claude --version`
# last, deliberately: the installer's exit code says only that the script ran,
# not that a working binary reached PATH — a `curl | bash` whose curl dies after
# partial output still exits 0.
RUN <<EOF
set -eux
curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}
claude --version
EOF

# Staging needs to write /out, so this half runs as root. `cp -a` preserves the
# launcher symlink and the agent ownership the install produced; the symlink's
# target is staged too, so it resolves inside the overlay on any base.
#
# The five ~/.claude subdirectories are the mount-point shape the kit's volume
# declarations need: a volume mounting on a *missing* path is auto-created as
# root, leaving the agent user unable to write. That alone is not enough — block
# volumes are formatted as ext4 and come out root-owned whatever the image had
# there — which is why the descriptor also carries a root-user startup chown.
USER root
RUN <<EOF
set -eux
mkdir -p /out/home/agent/.local/bin /out/home/agent/.local/share /out/etc/profile.d
cp -a /home/agent/.local/share/claude /out/home/agent/.local/share/claude
cp -a /home/agent/.local/bin/claude   /out/home/agent/.local/bin/claude

mkdir -p \
  /out/home/agent/.claude/projects \
  /out/home/agent/.claude/sessions \
  /out/home/agent/.claude/todos \
  /out/home/agent/.claude/shell-snapshots \
  /out/home/agent/.claude/statsig

chown -R 1000:1000 /out/home/agent

# MIGRATION NOTE: the workload sets four of these five as image ENV. A mixin
# cannot — its image config is not the composed image's — so they ride the overlay
# as profile.d exports, sourced by the base workload's login shell.
#
# The PATH line is the one the workload has no counterpart for. The workload's
# base exports ~/.local/bin on PATH as image ENV, so the install just works there;
# a mixin lands on whatever base the user picked, and this is where the install
# puts `claude`. A duplicate entry on a base that already has it is harmless.
#
#   CLAUDE_ENV_FILE          sourced by Claude Code before every Bash tool call,
#                            which is what lets an `export` the agent writes
#                            survive into the next command. The base creates the
#                            file and points BASH_ENV at it; this names it for
#                            Claude Code specifically, and the context file this
#                            kit ships documents the same path.
#   IS_SANDBOX               marks the environment for tools that check it.
#   DISABLE_TELEMETRY        usage/event reporting off. Fail-closed: the variable
#                            can only turn reporting off, never on. The broader
#                            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is
#                            deliberately not set (it also takes away /feedback,
#                            Projects and DesignSync — a feature cut rather than
#                            a telemetry decision), and neither is DO_NOT_TRACK
#                            (the cross-tool convention would silence every other
#                            tool in the sandbox, which is not this kit's call).
#   DISABLE_ERROR_REPORTING  crash reporting, which the variable above does not
#                            cover — the binary gates the two independently.
printf '%s\n' \
  'export PATH="$HOME/.local/bin:$PATH"' \
  'export CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh' \
  'export IS_SANDBOX=1' \
  'export DISABLE_TELEMETRY=1' \
  'export DISABLE_ERROR_REPORTING=1' \
  > /out/etc/profile.d/claude-mixin-env.sh
EOF

# The overlay: the install tree, the mount-point shape and the profile.d
# exports, landing on any base. No ENTRYPOINT — the base workload's launch
# command stays and the user runs `claude` from the shell.
FROM scratch
COPY --from=build /out /
