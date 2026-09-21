# syntax=docker/dockerfile:1

# Overlay recipe for the codex mixin: the same install the codex workload kit
# does, landed under /out and shipped as a `FROM scratch` delta that composes
# onto any base rather than as a root filesystem.
#
# The build stage is the workload's own base, verbatim. Two of the three things
# this recipe installs cannot be relocated by pointing an installer somewhere
# else — xdg-utils is an apt package, and apt owns where its files go — so the
# shape the guide prescribes applies: run the unmodified install on the
# workload's base, then copy the specific resulting paths into the overlay.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# xdg-utils, for the `xdg-open` that the BROWSER export below names. The
# package is one architecture-independent set of shell scripts with no
# dependencies once --no-install-recommends drops the X11 desktop-integration
# half, which is what makes copying /usr/bin/xdg-* out of it a faithful
# relocation rather than half an install: there is no library, no data
# directory, and nothing outside /usr/bin and /usr/share/man that xdg-open
# reads at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends xdg-utils \
 && rm -rf /var/lib/apt/lists/* \
 && command -v xdg-open \
 && mkdir -p /out/usr/bin \
 && cp -a /usr/bin/xdg-* /out/usr/bin/

# OpenAI's standalone installer, as the workload runs it, with CODEX_INSTALL_DIR
# pointed into the overlay tree instead of at /home/agent/.local/bin.
#
# The path moves on purpose: /usr/local/bin is where an overlay belongs — a
# mixin that wrote into /home/agent would land inside whatever the base (or a
# volume) has already put there — and it is on the PATH of any base carrying
# the platform floor. The workload keeps its own path because it owns its home
# directory.
#
# CODEX_NON_INTERACTIVE=true is required, not cosmetic: left unset the
# installer asks which shell profile to append PATH to, and a build has no TTY
# to answer that prompt — the RUN would hang.
#
# The install is pinned, via the kit's `version` arg, and to the same release
# the codex workload pins — the two ship the same CLI under the same provide
# name, so they have to agree. CODEX_RELEASE is the installer's own documented
# knob for this (`install.sh --help`: "Version to install; overridden by
# --release"), so the pin goes through the vendor's supported path rather than
# around it. No default on the ARG: an empty CODEX_RELEASE means `latest` to
# the installer, and a float underneath a descriptor publishing
# `codex@${{ kit.args.version }}` is worse than floating outright.
#
# `--version` last, deliberately: the installer's exit code says only that the
# script ran, not that a usable binary landed. And it is COMPARED against the
# pin rather than merely printed. `codex --version` prints "codex-cli
# <version>", so the second field is the number to match.
# CODEX_INSTALL_DIR alone does NOT relocate the install, and this overlay
# shipped a dangling symlink until that was understood. The installer puts only
# a launcher symlink in CODEX_INSTALL_DIR; the release tree it points at goes
# to $CODEX_HOME/packages/standalone/releases/<version>-<target>, and
# CODEX_HOME defaults to $HOME/.codex — /root/.codex in this root build stage,
# which is outside /out and so never reached the overlay. `COPY --from=build
# /out /` then landed /usr/local/bin/codex pointing into a /root that does not
# exist on the composed base, and `codex` was command-not-found there. The
# build-stage `--version` check passed the whole time, because in THAT stage
# /root/.codex was real.
#
# So both knobs point into the staging tree. /opt is where an overlay belongs,
# for the reason above: /home/agent may be a mounted volume on the base this
# lands on. The runtime CODEX_HOME stays /home/agent/.codex — the profile.d
# export below, matching the workload — so this path is the install location
# only, not the agent's config directory.
ARG CODEX_VERSION
ENV CODEX_INSTALL_DIR=/out/usr/local/bin
ENV CODEX_HOME=/out/opt/codex-cli
RUN <<EOF
set -eux
[ -n "${CODEX_VERSION}" ] || { echo "CODEX_VERSION must be set" >&2; exit 1; }

mkdir -p /out/usr/local/bin
CODEX_NON_INTERACTIVE=true CODEX_RELEASE="${CODEX_VERSION}" \
  sh -c "$(curl -fsSL https://chatgpt.com/codex/install.sh)"

# Before the symlinks are rewritten, while they still resolve in this stage.
installed=$(/out/usr/local/bin/codex --version | awk '{print $2}')
[ "$installed" = "${CODEX_VERSION}" ] || {
  echo "installed codex $installed != pinned ${CODEX_VERSION}" >&2; exit 1; }

# The installer writes ABSOLUTE symlinks, so both of the ones it created carry
# the /out staging prefix and would dangle once the overlay is copied onto a
# base. Strip it. Rewritten by reading each link rather than by spelling the
# targets out, because the release directory name embeds the Rust target triple
# (0.155.1-aarch64-unknown-linux-musl) and so differs per architecture:
#
#   /out/usr/local/bin/codex  -> /out/opt/.../standalone/current/bin/codex
#   /out/opt/.../current      -> /out/opt/.../releases/<version>-<target>
for link in /out/usr/local/bin/codex /out/opt/codex-cli/packages/standalone/current; do
  ln -sfn "$(readlink "$link" | sed 's#^/out##')" "$link"
  case "$(readlink "$link")" in /out/*) echo "unrewritten staging path in $link" >&2; exit 1 ;; esac
done

# The release archive records the publisher's CI uid (1001) and tar preserves
# it, so the staged tree arrives owned by an account that does not exist here.
# Harmless in a build stage; as image content on an unknown base that id may be
# a real account, and a file's owner can rewrite it whatever its mode says.
chown -R 0:0 /out/opt/codex-cli

# Installer scratch (extracted arg0 helper copies), not part of the install.
rm -rf /out/opt/codex-cli/tmp

mkdir -p /out/usr/local/share/npm-global/bin
ln -sf /usr/local/bin/codex /out/usr/local/share/npm-global/bin/codex
EOF

# v2's environment.variables. A mixin's image config does not become the
# composed image's, so the exports ride the overlay and the base's login shell
# sources them.
#
# BROWSER names the xdg-open copied in above — there is still no browser and no
# display, so a link does not literally open, but xdg-open says so and exits
# non-zero, which is a diagnosable answer and Codex prints the URL.
# GIT_TERMINAL_PROMPT=0 keeps git from opening /dev/tty for a credential prompt
# nobody can answer, which would freeze Codex's TUI.
#
# IS_SANDBOX is deliberately absent: the v2 codex kit never declared it, unlike
# the sibling claude and cursor kits.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/codex-env.sh <<'EOF'
export BROWSER=xdg-open
export CODEX_HOME=/home/agent/.codex
export GIT_TERMINAL_PROMPT=0
EOF

# The overlay: the CLI (its launcher shim plus the standalone release tree
# under /opt that the shim resolves to), xdg-open, the npm-global shim
# codex-app-server's wrapper execs, and the profile.d exports — landing on any
# base.
FROM scratch
COPY --from=build /out /
