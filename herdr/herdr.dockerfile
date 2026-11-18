# syntax=docker/dockerfile:1
# The herdr workload's content: the `shell` kit's own image, a Docker Hardened
# Image published as docker.io/sbx/shell, with herdr on top and herdr as the
# launch command. The base carries the platform floor (bash, the agent user,
# git, a CA store), a Docker engine, and the packages agent mixins `require`;
# keeping it the same as `shell`'s is what lets a mixin's requirements resolve
# on either. The tag floats, so a rebuild picks up a patched `shell`.
FROM docker.io/sbx/shell:latest

# TARGETARCH is BuildKit's per-platform arg: it names the platform each leg of
# a multi-platform build targets, so the herdr download below picks the
# matching release asset. The steps up to `USER agent` run as root.
ARG TARGETARCH
USER root

# Supplied by the frontend from the descriptor's `version` arg (buildArg). The
# default serves a plain `docker build` of this file and moves with the
# descriptor's default and the two digests below.
ARG HERDR_VERSION=0.9.5

# SHA-256 of herdr-linux-x86_64 and herdr-linux-aarch64 for the default version:
# the digests GitHub records for the official release assets, which match the
# `sha256` values https://herdr.dev/latest.json lists for them. Bumping the
# version without updating both fails the build on purpose.
ARG HERDR_SHA256_AMD64=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
ARG HERDR_SHA256_ARM64=17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c

# The release assets are bare static (musl) executables, not archives, so the
# download is the binary itself. Root-owned in /usr/local/bin: herdr's own
# updater, run as the agent user, cannot replace it without sudo, and under a
# deny-all policy it cannot reach a release either.
#
# `herdr --skill` prints the agent skill that matches this exact binary. Written
# here rather than kept in the repo, it cannot drift from the CLI it describes;
# herdr.yaml declares the directory as an agent-skill@1 source.
RUN <<EOT
set -eux
case "${TARGETARCH}" in
  amd64) asset=herdr-linux-x86_64;  sha="${HERDR_SHA256_AMD64}" ;;
  arm64) asset=herdr-linux-aarch64; sha="${HERDR_SHA256_ARM64}" ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/herdr \
  "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/${asset}"
echo "${sha}  /tmp/herdr" | sha256sum -c -
install -o root -g root -m 0755 /tmp/herdr /usr/local/bin/herdr
rm -f /tmp/herdr

skill=/usr/local/share/herdr-kit/skills/herdr
install -d -o root -g root -m 0755 "${skill}"
herdr --skill > "${skill}/SKILL.md"
chmod 0644 "${skill}/SKILL.md"
grep -qx 'name: herdr' "${skill}/SKILL.md"
EOT

# herdr's config, baked rather than written at create: it is part of what this
# image is, and a plain `docker run` gets it too. Every key is in
# `herdr --default-config`; the comments say why each is set.
#
# Two copies. The pristine one stays root-owned beside the skill, so a user who
# breaks or deletes the live one can copy it back. The live one, and both
# directories above it, are the agent's: herdr writes to the file itself (its
# settings screen saves there) and keeps its logs and session state beside it.
COPY --chmod=0644 <<'EOT' /usr/local/share/herdr-kit/config.toml
# herdr's settings for this sandbox, from the herdr kit. They are yours to
# change: herdr reads this file when its server starts, and
# `herdr server reload-config` applies an edit to a running server.
# `herdr --default-config` prints every key with its default, and
# /usr/local/share/herdr-kit/config.toml is this file as the kit shipped it.

# No first-run setup screen between `sbx run` and a usable pane.
onboarding = false

[terminal]
# Every pane is a bash login shell, like the one the `shell` kit opens.
# herdr's defaults would start $SHELL, or /bin/sh when it is unset, and
# never as a login shell on Linux.
default_shell = "/bin/bash"
shell_mode = "login"

[update]
# No background requests to herdr.dev. herdr is pinned in the image, so an
# update notice would have nothing to act on, and agent detection stays
# the rules built into this version.
version_check = false
manifest_check = false

[ui.sound]
# A sandbox has no audio device.
enabled = false
EOT
RUN install -d -o agent -g agent /home/agent/.config /home/agent/.config/herdr \
 && install -o agent -g agent -m 0644 /usr/local/share/herdr-kit/config.toml \
      /home/agent/.config/herdr/config.toml

# Neither is set by the base. herdr starts panes from `default_shell` above,
# falls back to $SHELL, and without it to /bin/sh, which is dash here. So this
# covers a config that has lost that line, a plain `docker run`, and anything
# else that asks for the user's shell. LANG gives the panes, and everything
# else in the sandbox, a UTF-8 locale; C.UTF-8 is the one the base ships. TERM
# and COLORTERM stay unset: herdr sets both in every pane it starts, and sbx
# passes the host terminal's to an interactive session.
ENV SHELL=/bin/bash \
    LANG=C.UTF-8

# Overrides the base's `shell`: sbx reads flavor as the image's agent
# identifier, so it names this kit. com.docker.sandboxes.start-docker=true is
# inherited from the base, which is what starts the Docker engine.
LABEL com.docker.sandboxes.flavor="herdr"

USER agent

# The launch command, checked as sbx starts it: found on PATH and run as the
# agent user. The build gives it no network, so a launcher that needs a
# download to start fails here. It must exit 0 and print the pinned version.
# Running it proves the download is an executable for this platform; the pin
# is a claim the descriptor publishes, so the build enforces it against what 
# ships.
RUN --network=none <<EOT
set -eux
command -v herdr
version=$(herdr --version)
test "${version}" = "herdr ${HERDR_VERSION}"
EOT

# The working directory sbx@1 asks a runtime to place the workspace at: a
# directory of its own under the agent's home, not the home itself, which holds
# herdr's config, logs and session state. The base declares the same path; it is
# restated because the image config is this kit's launch contract. A runtime
# that keeps the workspace at its host path starts the session there instead,
# and herdr's first pane opens wherever the session starts.
WORKDIR /home/agent/workspace

# Bare `herdr`: it starts herdr's background server when none is running, then
# attaches to it. Detaching (ctrl+b q) leaves the server and every pane running,
# and the next attach reaches the same session. A v3 workload takes its launch
# binary from the entrypoint, so it is stated here rather than inheriting the
# base's `bash -c 'exec "$@"'` wrapper, and setting it clears the base's CMD,
# `bash -l`. herdr needs a terminal; without one, run a subcommand such as
# `herdr server`.
ENTRYPOINT ["herdr"]
