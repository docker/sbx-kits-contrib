# syntax=docker/dockerfile:1
# The herdr workload's content: what the `shell` kit builds, the shell-docker
# template with Docker's certificate-trust fixes, with herdr on top and herdr as
# the launch command. The base carries the platform floor (bash, the agent
# user, git, a CA store), a Docker engine, and the packages agent mixins
# `require`; keeping it the same as `shell`'s is what lets the same mixins
# compose onto either.
FROM dhi.io/sbx-templates:shell-docker

# TARGETARCH is BuildKit's per-platform arg: it names the platform each leg of
# a multi-platform build targets, so the herdr download below picks the
# matching release asset. The steps up to `USER agent` run as root.
ARG TARGETARCH
USER root

# ==== BEGIN BASE PATCHES =====================================================
# A temporary patch over dhi.io/sbx-templates:shell-docker, for fixes the
# template does not ship yet: Docker's certificate-trust fixes, which DHI's apt
# repository carries ahead of the template.
#
# The RUN block below is the `shell` kit's certificate-trust step, copied word
# for word from shell/shell.dockerfile, so the two images carry the same
# packages and every mixin that composes onto `shell` composes onto herdr too.
#
# Once the template ships the fixes, delete this whole section, from the BEGIN
# line to the END line, together with the README's mention of it. Keep the
# lines above the section, which herdr's install needs too; the rest of the
# recipe builds without it.
RUN <<EOF
set -eu
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    gh \
    nodejs-24 \
    python3-pip \
    python3-pip-whl \
    uv

# Accept newer DHI revisions while refusing a stale repository or cache.
# Refresh the pip wheel too, so newly created virtual environments inherit
# the fixed vendored certificate bundle. Docker and containerd must also
# be rebuilt with patched Go; updating the installed compiler is insufficient.
for requirement in \
    ca-certificates=20250419+deb13u1 \
    containerd.io=2.4.2-1 \
    docker-buildx-plugin=0.38.1-0 \
    docker-ce=5:29.9.2-0 \
    docker-ce-cli=5:29.9.2-0 \
    docker-compose-plugin=5.6.1-0 \
    gh=2.103.0-0 \
    nodejs-24=24.22.1-0 \
    python3-pip=26.2.2-0 \
    python3-pip-whl=26.2.2-0 \
    uv=0.13.4-0
do
    package=${requirement%%=*}
    minimum=${requirement#*=}
    dpkg --compare-versions "$(dpkg-query -W -f='${Version}' "$package")" ge "$minimum"
done
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
# ==== END BASE PATCHES =======================================================

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
# The version check runs the binary, which proves the download is an executable
# for this platform and not only bytes with the right digest. The pin is a claim
# the descriptor publishes, so the build enforces it against what ships.
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
test "$(herdr --version)" = "herdr ${HERDR_VERSION}"

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

# Neither is set by the base. Without SHELL, bash fills it in from the agent's
# passwd entry, which names /bin/sh, and /bin/sh is dash here. herdr starts
# panes from `default_shell` above and falls back to $SHELL, so this covers a
# config that has lost that line, a plain `docker run`, and anything else that
# asks for the user's shell. LANG gives the panes, and everything else in the
# sandbox, a UTF-8 locale; C.UTF-8 is the one the base ships. TERM and
# COLORTERM stay unset: herdr sets both in every pane it starts, and sbx passes
# the host terminal's to an interactive session.
ENV SHELL=/bin/bash \
    LANG=C.UTF-8

# Overrides the base's `shell`: sbx reads flavor as the image's agent
# identifier, so it names this kit. com.docker.sandboxes.start-docker=true is
# inherited from the base, which is what starts the Docker engine.
LABEL com.docker.sandboxes.flavor="herdr"

USER agent

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
# base's `tini --`, and setting it clears the base's CMD. herdr needs a
# terminal; without one, run a subcommand such as `herdr server`.
ENTRYPOINT ["herdr"]
