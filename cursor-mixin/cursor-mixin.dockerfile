# syntax=docker/dockerfile:1

# Overlay recipe for the cursor mixin: the same vendor install the cursor
# workload kit does, landed under /out and shipped as a `FROM scratch` delta
# that composes onto any base rather than as a root filesystem of its own.
#
# The build stage is the workload's own base, verbatim.
#
# Cursor's installer resolves the platform itself and lays the agent under
# $HOME/.local — a versions tree under .local/share plus a symlink in
# .local/bin. It takes no target-directory option, so the relocation runs it
# against a scratch HOME and moves the tree afterwards, rather than trying to
# talk the installer into writing somewhere else.
#
# The tree lands at a stable /opt path with a /usr/local/bin shim: an overlay
# that wrote into /home/agent would land inside whatever the base (or a mounted
# volume) has already put there.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root

# Two departures from the vendor's published one-liner, carried over from the
# workload recipe, both about failing closed rather than open:
#
#   - `-L`. `-f` does not treat a 3xx as an error, so without `-L` a redirect
#     would pipe an empty body into bash, bash would exit 0, and `pipefail`
#     would see nothing wrong — an overlay with no agent in it that built
#     "successfully".
#   - the `test -x` afterwards. A completed install command proves an exit
#     code, not an installed binary.
#
# The install floats: no version pin (and cursor-agent self-updates), which is
# why the descriptor's `provides: ["cursor"]` is unversioned and leans on its
# `version:` fallback.
RUN <<EOF
set -exo pipefail
mkdir -p /build /out/opt /out/usr/local/bin
HOME=/build bash -c 'curl -fsSL https://cursor.com/install | bash'
test -x /build/.local/bin/cursor-agent
cp -a /build/.local/share/cursor-agent /out/opt/cursor-agent
# The installer's bin entry points into the versions tree it just wrote, under
# the scratch HOME. Rewrite that prefix to the overlay's /opt path so the shim
# resolves once the tree has moved.
target=$(readlink /build/.local/bin/cursor-agent | sed 's#^.*/.local/share/cursor-agent#/opt/cursor-agent#')
ln -s "$target" /out/usr/local/bin/cursor-agent
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
