# syntax=docker/dockerfile:1.7
# pi as an overlay.
#
# Why the build stage is the workload's own base rather than a relocating
# install: `npm install -g` writes into the configured global prefix and
# leaves relative bin symlinks pointing into it, with no flag that relocates
# the result afterwards. So this takes the shape the guide prescribes for
# exactly that case -- run the unmodified install on the workload's own base,
# then copy the specific resulting paths into a scratch overlay. Everything
# lands at the absolute path it was built at, which is what keeps those
# symlinks resolving.
#
# WHAT THIS OVERLAY CANNOT CARRY: a Node runtime. The workload installs none
# either -- the shell templates already ship Node 22, which satisfies pi's
# `engines.node >= 22.19.0` -- so pi works on a base that has one and fails
# on a base that does not. There is no grammar to state that floor:
# provides/requires name kit capabilities, and no base workload provides an
# entry for its language runtimes. The workload kit (../pi) is the
# self-contained alternative.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER root

# pi's `find` tool is fd underneath. On first use pi probes the system for
# `fd` or `fdfind` and, finding neither, downloads a release binary from
# GitHub -- a host this kit's allowlist does not name, so the download cannot
# succeed and `find` is simply broken. Ubuntu's package is `fd-find` and it
# installs the binary as `fdfind`; pi's probe accepts that name as-is, and
# the `fd` symlink is for humans at the shell.
#
# The apt package's dpkg state does not travel into an overlay, but the
# binary does: fdfind is a Rust build that links only libc and libgcc_s,
# which every glibc base carries. That is why this one apt install is worth
# copying out rather than leaving to the base, unlike a package with a deep
# library closure.
RUN apt-get update && \
    apt-get install -y --no-install-recommends fd-find && \
    rm -rf /var/lib/apt/lists/*

# Rolling updates by design: pi tracks the `latest` dist-tag. BuildKit
# re-downloads this URL on every build to compute its digest, so the install
# layer re-runs exactly when the fetched packument changes and is a cache hit
# otherwise. PI_VERSION is part of the URL, so overriding it reproduces a
# specific version and keeps the cache key stable. It is not a kit arg: the
# descriptor's provide is unversioned precisely because the default floats.
ARG PI_VERSION=latest
ADD --chmod=644 https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/${PI_VERSION} /tmp/pi-latest.json

# The install, unmodified from the workload recipe: the version comes out of
# the packument ADDed above rather than being re-resolved at RUN time, the
# install runs as agent because the template's global prefix is agent-owned
# (which is the ownership `pi update --self` and `pi install` need), and
# `pi --version` is the build-time gate -- npm only WARNS on an engines
# mismatch, so executing pi is what actually fails the build on a release
# this Node cannot run.
USER agent
RUN version="$(node -p 'require("/tmp/pi-latest.json").version')" && \
    npm install -g "@earendil-works/pi-coding-agent@${version}" && \
    pi --version

USER root

# The specific resulting paths.
#
# Directory ownership is mirrored from the build stage with
# `chown --reference` rather than left as root: an overlay's directory entry
# carries its own ownership onto the composed image, so a root-owned
# /home/agent/... prefix would land on top of the base's agent-owned one and
# take `pi update --self` with it. Copying the metadata from the same tree
# the files came out of is what keeps that from happening whatever the
# template's prefix turns out to be.
#
# The /usr/local/bin/pi shim is a bin shim rather than a profile.d PATH
# export: the global bin dir is on PATH on the shell templates, but a mixin
# lands on any base and /usr/local/bin is on every one of them. Guarded
# because a prefix of /usr/local would make it a self-referential link.
RUN set -eu; \
    prefix="$(npm prefix -g)"; \
    mkdir -p "/out${prefix}/lib/node_modules" "/out${prefix}/bin" /out/usr/local/bin /out/usr/bin; \
    for d in "${prefix}" "${prefix}/bin" "${prefix}/lib" "${prefix}/lib/node_modules"; do \
      if [ -d "$d" ]; then chown --reference="$d" "/out${d}"; fi; \
    done; \
    cp -a "${prefix}/lib/node_modules/@earendil-works" "/out${prefix}/lib/node_modules/@earendil-works"; \
    cp -a "${prefix}/bin/pi" "/out${prefix}/bin/pi"; \
    [ "${prefix}/bin/pi" = /usr/local/bin/pi ] || ln -s "${prefix}/bin/pi" /out/usr/local/bin/pi; \
    cp -a "$(command -v fdfind)" /out/usr/bin/fdfind; \
    ln -s /usr/bin/fdfind /out/usr/local/bin/fd

# The overlay: the agent, its bin shim and fd, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays, and the user runs
# `pi` from the shell.
FROM scratch
COPY --from=build /out /
