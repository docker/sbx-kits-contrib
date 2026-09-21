# syntax=docker/dockerfile:1.7
# Packages through SFW as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to install anything. v3 lifts that, so the two hooks that were pure content
# build here instead of at every sandbox create: the version+digest-pinned sfw
# binary, and the shims and shell wrappers, which are static files with nothing
# create-time in them. What that buys is no per-create download, GitHub out of
# the kit's install-phase permission surface entirely, and a binary whose digest
# is fixed in the published layer rather than re-verified in every sandbox.
#
# WHAT THIS OVERLAY CANNOT CARRY, both still hooks in packages-through-sfw.yaml:
#
#   * the apt prerequisites. apt packages are not copyable content -- they need
#     the composed base's own dpkg database, and an overlay cannot carry a
#     package's shared-library closure. The shims here are wrappers around the
#     node, python and pip the composed base ends up with, not substitutes for
#     them.
#   * the ~/.bashrc line. An overlay's file entries replace the base's rather
#     than merging with them, so shipping /home/agent/.bashrc would shadow
#     whatever the composed workload put there instead of appending one line to
#     it. That hook is an append to a file this kit does not own, which is
#     exactly the thing content cannot express.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The pin the install hook carried, unchanged: the release version and the
# per-arch SHA256 of the asset. Bumping sfw means editing this line, both
# digests, and the `provides` entry in packages-through-sfw.yaml.
ARG SFW_VERSION=1.10.0
ARG TARGETARCH

USER root

# v2's second install hook. TARGETARCH rather than the hook's `uname -m`: this
# runs at build, where buildx sets it per platform, so `--platform
# linux/amd64,linux/arm64` resolves each leg to its own asset. The hook could
# only ever see the one sandbox it ran in.
#
# Digest-checked here exactly as it was there. The check has not become
# ceremonial by moving: it is what makes the published layer's content
# attributable to the upstream release rather than to whatever the release URL
# served on build day.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        asset="sfw-free-linux-x86_64"; \
        sha256=1ea16f15f1217bde66ac9c7d0262c7126b7bb1b2d60e14e8fa0982456139ae6e ;; \
      arm64) \
        asset="sfw-free-linux-arm64"; \
        sha256=d7e969c17e6d23ac1cb0dea81ff87ef9bca2d83570270d91aab14b2a7fb66ad4 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/sfw \
      "https://github.com/SocketDev/sfw-free/releases/download/v${SFW_VERSION}/${asset}"; \
    echo "${sha256}  /tmp/sfw" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    install -m 0755 /tmp/sfw /out/usr/local/bin/sfw; \
    rm -f /tmp/sfw; \
    /out/usr/local/bin/sfw --version

# v2's third install hook, byte-for-byte: the same quoted `<<'SCRIPT'` heredocs,
# which the writing shell does not expand, so `"$@"` and `$1` reach the shim
# files literally. Written straight into /out rather than into this stage's own
# /usr/local/bin, so the build stage keeps working npm and python3 of its own.
#
# One ordering consequence of moving this out of a hook: the shims now exist
# from the moment the overlay is composed, where v2 wrote them after the apt
# hook ran. That is safe in the direction that matters -- each shim delegates to
# the real tool on a restricted PATH (/usr/sbin:/usr/bin:/sbin:/bin), which is
# where apt puts nodejs, npm and python3-pip, so a shim that is asked to run
# before its tool exists fails exactly as the bare command would have.
RUN <<'EOF'
set -eu
mkdir -p /out/usr/local/lib/packages-through-sfw/shims /out/usr/local/bin /out/etc/profile.d

cat > /out/usr/local/lib/packages-through-sfw/shims/npm <<'SCRIPT'
#!/bin/sh
PATH="/usr/sbin:/usr/bin:/sbin:/bin" exec /usr/local/bin/sfw npm "$@"
SCRIPT

cat > /out/usr/local/lib/packages-through-sfw/shims/pip <<'SCRIPT'
#!/bin/sh
exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip "$@"
SCRIPT

cat > /out/usr/local/lib/packages-through-sfw/shims/pip3 <<'SCRIPT'
#!/bin/sh
exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip3 "$@"
SCRIPT

cat > /out/usr/local/lib/packages-through-sfw/shims/python3 <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then
  shift 2
  exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip "$@"
fi
PATH="/usr/sbin:/usr/bin:/sbin:/bin" exec python3 "$@"
SCRIPT

# The PATH entries themselves. /usr/local/bin precedes /usr/bin on every
# template's PATH, which is the whole mechanism: a tool invoked by name resolves
# to the shim, and the shim's restricted PATH is what keeps sfw from calling it
# back.
install -m 0755 /out/usr/local/lib/packages-through-sfw/shims/npm     /out/usr/local/bin/npm
install -m 0755 /out/usr/local/lib/packages-through-sfw/shims/pip     /out/usr/local/bin/pip
install -m 0755 /out/usr/local/lib/packages-through-sfw/shims/pip3    /out/usr/local/bin/pip3
install -m 0755 /out/usr/local/lib/packages-through-sfw/shims/python3 /out/usr/local/bin/python3

# For interactive shells. Functions rather than aliases so they apply in
# non-interactive sub-shells of a login shell too; each one delegates to the
# PATH shim above, so there is one implementation, not two. The `~/.bashrc`
# line that sources this file stays a hook -- see the header.
cat > /out/etc/profile.d/packages-through-sfw.sh <<'SCRIPT'
# Route package-manager installs through Socket Firewall Free.
if [ -x /usr/local/bin/npm ]; then
  npm() { /usr/local/bin/npm "$@"; }
fi
if [ -x /usr/local/bin/pip ]; then
  pip() { /usr/local/bin/pip "$@"; }
fi
if [ -x /usr/local/bin/pip3 ]; then
  pip3() { /usr/local/bin/pip3 "$@"; }
fi
SCRIPT
chmod 0644 /out/etc/profile.d/packages-through-sfw.sh
EOF

# The overlay: one pinned binary, four shims and a profile.d snippet, landing on
# any base. Nothing is staged under the agent's home -- /usr/local and
# /etc/profile.d are what a mixin landing on an unknown base should prefer,
# since whatever is at /home/agent may be a mounted volume, and the one thing
# this kit does have to write there stays a hook for that reason. No ENTRYPOINT
# -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
