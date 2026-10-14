# syntax=docker/dockerfile:1

# Overlay recipe for the `goose` mixin. The build stage fetches and verifies the
# release; the final stage is `FROM scratch` and carries only what lands on the
# workload's filesystem. A mixin's ENTRYPOINT, CMD, USER and WORKDIR are ignored
# when it is composed, so none are set here.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Staging writes outside $HOME, so this half runs as root: these bases run as the
# agent user, and a `mkdir /out` as that user fails.
USER root

# Supplied by the frontend from the descriptor's `version` arg (buildArg), with
# no default here, so the descriptor is the single source of the version.
ARG GOOSE_VERSION
ARG TARGETARCH

# SHA-256 of goose-<arch>-unknown-linux-musl.tar.gz for the default version. The
# release publishes no checksum file for these, so they are the digests GitHub
# records for the official assets. Bumping `version` without updating them fails
# the build on purpose.
#
# The musl build, not the gnu one, because this overlay lands on a base it does
# not control: a statically linked binary needs nothing from that base's libc.
# It is built with goose's `portable-default` feature set, which leaves out the
# in-process local-model inference of the gnu build; the sandbox talks to a
# hosted provider through the proxy, so nothing here uses it.
ARG GOOSE_SHA256_AMD64=777e49b6ae128fae06600f94bf51ff05c81572fce63c1581e9ea94bc49d64e42
ARG GOOSE_SHA256_ARM64=baeb3e1b188fce75b444af35b5955f255e68fde87f60a5ba01f032227618a4ed

# /usr/local/bin, not the agent's home: an overlay should prefer /usr/local, /opt
# and /etc/profile.d, since whatever is at /home/agent on the composed base may
# be a mounted volume.
RUN <<EOT
set -eux
[ -n "${GOOSE_VERSION}" ] || { echo "GOOSE_VERSION must be set" >&2; exit 1; }
case "${TARGETARCH}" in
  amd64) arch=x86_64;  sha="${GOOSE_SHA256_AMD64}" ;;
  arm64) arch=aarch64; sha="${GOOSE_SHA256_ARM64}" ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac
tarball="goose-${arch}-unknown-linux-musl.tar.gz"
mkdir -p /out/usr/local/bin
curl -fsSL -o "/tmp/${tarball}" \
  "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/${tarball}"
echo "${sha}  /tmp/${tarball}" | sha256sum -c -
tar -xzf "/tmp/${tarball}" --no-same-owner -C /out/usr/local/bin ./goose
rm -f "/tmp/${tarball}"
chown 0:0 /out/usr/local/bin/goose
chmod 0755 /out/usr/local/bin/goose

# The pin is a claim about content, so the build enforces it, against the binary
# that is about to ship. goose's state goes to a throwaway directory so the check
# leaves nothing behind under /root.
state="$(mktemp -d)"
GOOSE_PATH_ROOT="${state}" /out/usr/local/bin/goose --version | grep -q "${GOOSE_VERSION}"
rm -rf "${state}"
EOT

# A mixin's image config does not become the composed image's, so the export
# rides the overlay as a drop-in the base's login shell sources. There is no
# keyring daemon in the sandbox; the install hook also writes the same flag into
# config.yaml, which covers launches that do not source /etc/profile.d.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/goose-env.sh <<'EOT'
export GOOSE_DISABLE_KEYRING=1
EOT

# ~/.agents, carried as an empty directory. goose.yaml declares
# ~/.agents/skills as agent-skills@1 and the host binds its skills store there; a
# bind target that does not exist gets its whole path created by the runtime as
# root, when the container starts and so before any install hook runs. That is
# why the hook's own `mkdir -p` cannot stand in for this.
#
# Ownership is mirrored from the build stage with `chown --reference` rather than
# left as root, including the /home and /home/agent prefix: an overlay stamps
# every directory entry it carries onto the composed image, so shipping the leaf
# without its parents would land a root-owned /home/agent on the base and take
# the agent's own home with it.
RUN set -eu; \
    mkdir -p /out/home/agent/.agents; \
    for d in /home /home/agent; do chown --reference="$d" "/out${d}"; done; \
    chown --reference=/home/agent /out/home/agent/.agents

# The overlay: the static CLI and the profile.d export, landing on any base.
FROM scratch
COPY --from=build /out /
