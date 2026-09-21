# syntax=docker/dockerfile:1

# Overlay recipe for the cursor mixin: the same vendor install the cursor
# workload kit does, landed under /out and shipped as a `FROM scratch` delta
# that composes onto any base rather than as a root filesystem of its own.
#
# The build stage is the workload's own base, verbatim.
#
# The tree lands at a stable /opt path with a /usr/local/bin shim: an overlay
# that wrote into /home/agent would land inside whatever the base (or a mounted
# volume) has already put there.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# WHY THIS NO LONGER PIPES https://cursor.com/install INTO BASH. The kit's
# `version` arg pins the release, and that installer cannot be pinned: it takes
# no version argument and no version environment variable, and the endpoint
# ignores query parameters — `?version=` and `?v=` both return the current
# script unchanged. The release identifier is baked into the script body when
# the vendor generates it. Piping it while the descriptor published
# `cursor@${{ kit.args.version }}` would assert a version the content need not
# have, which is worse than floating.
#
# The change also removes a step this shape used to need. The installer lays
# the agent under $HOME/.local and takes no target-directory option, so the old
# recipe ran it against a scratch HOME, copied the tree out, and rewrote the
# symlink's prefix with sed to chase the move. Fetching the release directly
# lands it at its final /opt path in one step, and the shim is a fixed link
# rather than a rewritten one.
#
# What the script does, reproduced with the version as a parameter:
#
#   1. map uname to the vendor's arch spelling (x86_64 -> x64, aarch64 ->
#      arm64). TARGETARCH is the build's own answer to the same question, and
#      is what makes a cross-build stage the right tarball rather than the
#      builder's.
#   2. fetch https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz
#      and untar it with --strip-components=1 into the versions directory.
#   3. symlink the agent onto PATH. The script writes two names — `agent`, its
#      primary, and `cursor-agent`, which it labels legacy — but only
#      `cursor-agent` is staged, which is what this overlay shipped before the
#      pin and is the name this kit's descriptor and README use. `agent` is
#      generic enough to shadow something on a base this mixin has never seen,
#      and adding a name is not this change's business. The workload keeps
#      both, because there the installer's own two symlinks land in a home
#      directory the kit owns.
#
# Two departures from the vendor's one-liner survive the change, both about
# failing closed rather than open:
#
#   - `-L`. `-f` does not treat a 3xx as an error, so without `-L` a redirect
#     would leave tar reading an empty body, and `pipefail` is what turns that
#     into a failed build rather than an overlay with no agent in it.
#   - the assertion afterwards. A completed install proves an exit code, not an
#     installed binary — so the staged binary is executed and its reported
#     version compared against the pin. `cursor-agent --version` prints the
#     identifier bare, on one line, which is exactly the string in the URL
#     above.
ARG CURSOR_VERSION
ARG TARGETARCH
RUN <<EOF
set -exo pipefail
[ -n "${CURSOR_VERSION}" ] || { echo "CURSOR_VERSION must be set" >&2; exit 1; }

case "${TARGETARCH}" in
  amd64) arch=x64 ;;
  arm64) arch=arm64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

dir="/out/opt/cursor-agent/versions/${CURSOR_VERSION}"
mkdir -p "$dir" /out/usr/local/bin
curl -fsSL "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/$arch/agent-cli-package.tar.gz" \
  | tar --strip-components=1 -xzf - -C "$dir"

# An absolute link to where the tree lands on the composed base, not to where
# it sits in this stage: /out is the staging root and disappears at COPY.
ln -s "/opt/cursor-agent/versions/${CURSOR_VERSION}/cursor-agent" /out/usr/local/bin/cursor-agent

test -x "$dir/cursor-agent"
installed=$("$dir/cursor-agent" --version)
[ "$installed" = "${CURSOR_VERSION}" ] || {
  echo "installed cursor-agent $installed != pinned ${CURSOR_VERSION}" >&2; exit 1; }

# The vendor archive records its build account's uid (2000) and tar preserves
# it, so the staged tree arrives owned by an account that does not exist here.
# Harmless in a build stage; as image content on an unknown base that id may be
# a real account, and a file's owner can rewrite it whatever its mode says.
chown -R 0:0 /out/opt/cursor-agent
EOF

# v2's environment.variables. A mixin's image config does not become the
# composed image's, so the exports ride the overlay and the base's login shell
# sources them.
#
# AGENT_CLI_CREDENTIAL_STORE=memory is load-bearing rather than cosmetic: left
# unset, Cursor reads its file-backed store, JWT-validates what it finds, fails
# on the proxy sentinel, and re-prompts for login — exactly the prompt a
# resolved credential is supposed to remove.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/cursor-env.sh <<'EOF'
export IS_SANDBOX=1
export AGENT_CLI_CREDENTIAL_STORE=memory
EOF

# The overlay: the agent tree, its bin shim and the profile.d exports, landing
# on any base.
FROM scratch
COPY --from=build /out /
