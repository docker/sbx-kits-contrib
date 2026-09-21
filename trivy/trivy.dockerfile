# syntax=docker/dockerfile:1
# The trivy workload's content. The v2 kit shipped no Dockerfile at all: it
# pointed `sandbox.image` straight at this published template and installed
# the scanner from a setup.install hook. A v3 workload must have content, so
# this recipe states that template as its base -- v2's `sandbox.image`,
# carried over verbatim -- puts v2's `sandbox.entrypoint` in the slot the
# image config already owns, and performs the install itself.
#
# The template carries the platform floor sbx@1 asks for: bash at /bin/bash,
# the agent user at uid 1000, git, and a CA store.
FROM docker/sandbox-templates:shell-docker

# Keep these two in step with ../trivy-mixin/trivy-mixin.dockerfile, which
# carries the same pin for the overlay form, and with the `provides` entry in
# trivy.yaml. Bumping is the edit the README documents: TRIVY_VERSION, both
# SHA256s from the release's checksums.txt, and the provide, together.
ARG TRIVY_VERSION=0.70.0
ARG TARGETARCH

# v2's hook said `user: "0"`: the tarball is extracted into /usr/local/bin,
# which is root's on this base and on every base.
USER root

# THE INSTALL, MOVED OUT OF THE LIFECYCLE HOOK.
#
# It stayed a hook through the v3 migration on the reasoning that a
# create-time install is what gives the install/runtime phase split something
# to do -- the release hosts open for the length of one command and close
# before the shell starts. Building it instead is strictly better on the same
# axis: the hosts are not in the sandbox's policy at all, in any phase,
# because the download is the builder's traffic. A sandbox created from this
# kit can no longer reach github.com even for the length of a hook, and the
# scanner it runs is bytes this image was published with rather than bytes
# fetched into a live sandbox. ../trivy-mixin has always done it this way;
# this is the workload matching it.
#
# What does NOT change is the pin. Why not the official `install.sh`: that
# pattern (curl|sh) is exactly what TeamPCP weaponized in March 2026 against
# tag-rewriteable references. The release is pinned by version AND SHA256, in
# the kit, in git -- the same version and the same two digests the hook
# carried, verified the same way, just earlier.
#
# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever
# see the one sandbox it ran in.
#
# The `chown` is the one line the hook did not have, and it is worth adding
# now that this runs at build: Aqua's release tarball records its CI user
# (uid 1001) as the owner, and `tar` as root honors that, so the hook left a
# binary in /usr/local/bin owned by a uid that is nobody in particular inside
# a sandbox -- and would be writable by whoever 1001 turned out to be there.
# Read out of the exported layer, not assumed.
#
# `trivy --version` last, as in the hook: the download's exit code says the
# bytes arrived, not that they run on this platform.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        tarball="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
        sha256=8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9 ;; \
      arm64) \
        tarball="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
        sha256=2f6bb988b553a1bbac6bdd1ce890f5e412439564e17522b88a4541b4f364fc8d ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/trivy.tgz \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${tarball}"; \
    echo "${sha256}  /tmp/trivy.tgz" | sha256sum -c -; \
    tar -C /usr/local/bin -xzf /tmp/trivy.tgz trivy; \
    rm /tmp/trivy.tgz; \
    chown 0:0 /usr/local/bin/trivy; \
    chmod 0755 /usr/local/bin/trivy; \
    trivy --version

# Back to the base's own user, and deliberately the last USER in the file: the
# root above is for the extraction only, and the identity this image publishes
# -- the one sbx@1 asks the host to honor -- is `agent`, as it was in v2.
USER agent

# v2's sandbox.entrypoint: drop into bash with trivy on PATH and the
# workspace as cwd. Run `trivy fs .` to scan. Setting ENTRYPOINT also clears
# the CMD inherited from the base, so nothing is appended to it.
ENTRYPOINT ["bash", "-l"]
