# syntax=docker/dockerfile:1.7
# code-server as an overlay.
#
# MIGRATION NOTE: this recipe used to carry only the VS Code user settings,
# because code-server itself came from an install hook -- the v2 shape, where a
# mixin had no content mechanism and a hook was the only way to install
# anything. Both installs are build-time content now: the editor and the
# preinstalled extension are ordinary files that need nothing from sandbox-create
# time. What that buys is no per-create download of a ~100 MB deb and a ~235 MB
# extension, an install-phase network grant that disappears entirely (the
# descriptor's network policy is runtime-only now), and a kit whose editor
# version is fixed and scannable at publish rather than resolved afresh in every
# user's sandbox.
#
# WHAT STAYED A HOOK: the startup wrapper, which bakes the create-time
# WORKSPACE_DIR into the argv, and the background start. Neither is content --
# see code-server.yaml.
#
# MIGRATION NOTE: the build stage was busybox when this file only had to stage a
# JSON file. It is the workload's own base now, because the work moved here
# needs curl, dpkg and a glibc userland to run the upstream installer and then
# run code-server itself to resolve an extension. Same base as ../claude, the
# workload this mixin layers onto.
#
# The assembly stage is here to own the result precisely: BuildKit applies a
# COPY --chown to every parent directory it creates, so copying straight into a
# scratch stage would hand /home itself to the agent. Staging under /out and
# chowning only the agent's own subtree leaves /home as the base has it, which
# is what v2's create-time install into an existing tree did.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER root

# THE PIN. The kit's `version` arg arrives as this build arg: code-server.yaml
# validates its shape and expands the same value into `provides` and into its own
# `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an empty
# fallback is the failure this pin exists to prevent -- the script would resolve
# the latest release while the descriptor went on asserting a number. A missing
# value fails the build instead; see the guard below.
ARG CODE_SERVER_VERSION

# v2's first install hook, plus the pin.
#
# HOW THE PIN REACHES THE INSTALLER: as `--version X.X.X`, which the script's own
# usage block documents as "Install a specific version instead of the latest".
# Without it the script calls echo_latest_version(), which follows
# github.com/coder/code-server/releases/latest and strips the tag's `v`; with it,
# that call is skipped and the release asset URL is built from this value, so a
# version naming no release fails the download. The `v` is the script's to add
# back -- it fetches `download/v$VERSION/code-server_${VERSION}_$ARCH.deb` -- and
# is not part of the arg, because SPEC-v3 §5.2 admits no `v` prefix in the
# version this kit publishes.
#
# What actually lands, checked rather than assumed: on Ubuntu the script fetches
# the release .deb from GitHub and `dpkg -i`s it into /usr/lib/code-server, with
# /usr/bin/code-server a three-line shim execing it. The deb declares no
# Depends: it carries its own node, so it is self-contained content an overlay
# can carry. It also ships systemd units and prints instructions for them; this
# kit does not use them -- the descriptor starts code-server from a background
# startup hook, which is what makes the declared port answer without an init
# system -- so the units are not staged.
#
# The `--version` call was already here as a gate, because the installer's exit
# code says the script ran and not that a working binary reached PATH. It is now
# also the pin's check: the descriptor publishes
# `code-server@${CODE_SERVER_VERSION}`, so an install that landed a different
# release would ship a provide that lies about its own content -- the one failure
# mode worse than floating, and the objection the descriptor used to raise
# against pinning at all.
#
# `code-server --version` prints `<version> <commit> with Code <code version>`,
# so the first field of that line is the number to match -- but it is not
# reliably the first LINE. On a first run the editor writes its default
# config.yaml and logs that to stdout above the version ("[<timestamp>] info
# Wrote default config file to ..."), which is the same first-run write the
# staging step below is careful not to stage. Hence the first line that starts
# with a digit rather than line 1: a log prefix can appear, a version cannot
# begin with anything else.
RUN <<EOF
set -eux
[ -n "${CODE_SERVER_VERSION}" ] || { echo "CODE_SERVER_VERSION must be set" >&2; exit 1; }
curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "${CODE_SERVER_VERSION}"
reported="$(code-server --version)"
echo "code-server --version: $reported"
installed="$(printf '%s\n' "$reported" | awk '/^[0-9]/{print $1; exit}')"
[ "$installed" = "${CODE_SERVER_VERSION}" ] || {
  echo "pin mismatch: descriptor says ${CODE_SERVER_VERSION}, binary reports '$reported'" >&2
  exit 1
}
EOF

# v2's second install hook, at the same `user: "1000"` it declared, which is
# what puts the extension in the agent's own extensions directory rather than
# root's. code-server resolves `anthropic.claude-code` from open-vsx and
# unpacks the platform-specific build for TARGETPLATFORM.
USER agent
RUN code-server --install-extension anthropic.claude-code

USER root

# v2's `files/home/` tree, landing where the v2 convention put it:
# /home/agent/<relative path>, so settings.json stays at
# /home/agent/.local/share/code-server/User/settings.json. The agent must own it
# -- code-server rewrites this file when a setting is changed in the UI -- and
# ownership is applied by the stanza below, by number, starting exactly at the
# agent's home. Deliberately no `--chown` here: BuildKit would stamp uid 1000
# onto /out/home too, and a `chown -R /out/home/agent` cannot undo a parent.
COPY files/home/ /out/home/agent/

RUN <<'EOF'
set -eux

# Fail loudly rather than shipping an overlay with an editor-shaped hole in it.
test -x /usr/lib/code-server/bin/code-server
test -x /usr/bin/code-server

mkdir -p /out/usr/lib /out/usr/bin /out/home/agent/.local/share/code-server

# The deb's payload, at the absolute paths it was installed at -- /usr/bin/code-server
# execs /usr/lib/code-server/bin/code-server by absolute path, and the editor's
# own module resolution is relative to that tree.
cp -a /usr/lib/code-server /out/usr/lib/code-server
cp -a /usr/bin/code-server /out/usr/bin/code-server

# The extension, and only the extension. `--install-extension` also leaves
# machineid, logs/, coder-logs/, a CachedExtensionVSIXs/ copy of the .vsix, and
# -- the reason to be precise here -- ~/.config/code-server/config.yaml, which
# code-server generates on first run with a random password in it. Baking that
# into a published layer would ship one password to every sandbox. This kit runs
# with --auth none anyway, so the file is regenerated per sandbox and never
# staged. extensions.json records each extension by absolute path, which is why
# this lands at exactly the path it was built at.
ext=/home/agent/.local/share/code-server/extensions
test -f "$ext/extensions.json"
cp -a "$ext" /out/home/agent/.local/share/code-server/extensions

# Starts exactly at the agent's home: /out/home stays root-owned, as the base
# has it, and everything below is the agent's. Numeric because scratch carries
# no /etc/passwd for a name to resolve against.
chown -R 1000:1000 /out/home/agent
EOF

# The overlay: the editor, the preinstalled extension and the user settings, on
# any base. No ENTRYPOINT -- the base workload's launch command stays, and the
# descriptor's startup hook brings the editor up beside it.
FROM scratch
COPY --from=build /out /
