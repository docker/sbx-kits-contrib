# syntax=docker/dockerfile:1
# Amp as an overlay.
#
# This kit had no recipe at all until now: v2 mixins could carry no content,
# so an install hook was the only mechanism a mixin had, and the first v3 cut
# transcribed that faithfully. v3 lets a mixin carry an overlay, and Amp's
# installer reads nothing that exists only at sandbox-create time, so the hook
# was encoding the v2 limitation rather than a requirement of Amp's. Building
# it instead means no download on every sandbox create, no install-phase
# egress in the descriptor, layers that are digest-pinned and scannable, and a
# broken upstream installer failing at publish instead of in a sandbox.
#
# WHY THE INSTALL RELOCATES, where this repo's other agent mixins have to copy
# a $HOME-scoped tree out: install.sh opens with
#
#     AMP_HOME="${AMP_HOME:-$HOME/.amp}"
#     BIN_DIR="$AMP_HOME/bin"
#
# so the whole install tree is one variable away from anywhere. Pointing it at
# /opt/amp is what lets this overlay avoid the agent's home entirely -- which
# is what a mixin landing on an unknown base should prefer anyway, since
# whatever is at /home/agent there may be a mounted volume that would cover
# the overlay's content at create. It also sidesteps the cross-tree symlink
# the installer's PATH step leaves behind: the binary and its shim are the
# only two things this ships, and both are inside what it ships.
#
# The workload (../amp) deliberately does NOT relocate: it owns its root
# filesystem, so the faithful thing there is the install v2's hook performed,
# under the agent's own home.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN. The kit's `version` arg arrives as this build arg: amp-mixin.yaml
# validates its shape and expands the same value into `provides` and into its own
# `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an empty
# fallback is the failure this pin exists to prevent -- install.sh treats an unset
# AMP_VERSION as "install whatever the pointer says", so the install would float
# while the descriptor went on asserting a number. A missing value fails the
# build instead; see the guard in the RUN below.
ARG AMP_VERSION

# Root, because /opt belongs to root on every base this composes onto and the
# overlay has to ship it that way -- an overlay's directory entries override
# the base's, so a /opt or /opt/amp carrying uid 1000 would hand those
# directories to whoever uid 1000 turns out to be there. Nothing writes into
# the prefix at run time; see the self-update note below.
USER root

# The install, otherwise unmodified from the workload's. Notes on the parts
# that are not obvious:
#
#   - AMP_HOME is exported into the pipeline rather than set with ENV so it
#     stays what it is: a build-time instruction to the installer. Exporting
#     it into the composed sandbox would point the CLI's own updater at a
#     root-owned /opt the agent cannot write.
#   - install.sh still runs its PATH step after the download, and as root that
#     writes a symlink under /root and may append a PATH line to /root/.bashrc.
#     Neither is copied out; the shim below is what puts `amp` on PATH.
#   - The platform it picks comes from `uname` plus, on x86 only, an AVX2
#     probe of /proc/cpuinfo. Under emulation that probe reads the builder's
#     own CPU, so a cross-built linux/amd64 leg resolves to the
#     `linux-x64-baseline` binary -- slower, and correct on every x86-64.
#   - AMP_VERSION is exported for the same reason AMP_HOME is: it is an
#     instruction to install.sh, which opens with
#     `AMP_VERSION="${AMP_VERSION:-}"` and, when that is non-empty, takes it as
#     the version outright and builds the binary and checksum URLs from it
#     instead of fetching its version pointer. A build arg is already in this
#     RUN's environment and install.sh inherits it as a child process; the
#     export says so rather than leaving it to be inferred. A value naming no
#     published release fails the download.
#   - install.sh verifies its download against the SHA256 the release publishes
#     before it installs, so the fetch is checksummed as well as pinned.
#
# `test -x` is the first build-time gate: it pins the assumption that AMP_HOME is
# still the whole of the install prefix, so a change upstream fails the build
# here rather than shipping an overlay with no agent in it.
#
# The version comparison is the second, and it is the one the provide rests on:
# the descriptor publishes `amp@${AMP_VERSION}`, so an install that resolved to
# something else would ship an overlay whose provide lies about its own content
# -- the one failure mode worse than floating. The checksum above is not a
# substitute: it proves the bytes are the artifact published beside the version
# install.sh asked for, not that the artifact reports the release this kit names.
# `amp --version` prints `<version> (released <date>, <age> ago)`, so the first
# field is the number to match.
#
# This does execute a ~100 MB self-contained binary, which on a
# `--platform linux/amd64,linux/arm64` build means running the foreign leg under
# emulation -- the cost an earlier note here declined to pay when there was no
# pin to verify. It is a cheap call even so: the string it prints is baked into
# the binary (the "released ... ago" part is arithmetic on the timestamp inside
# its own version), so it reaches no network and returns in under a second
# natively. The overlay is still exercised where it counts as well: composed onto
# a bare ubuntu:24.04 and run as uid 1000, `amp --version` reports this pin.
RUN set -eux; \
    [ -n "$AMP_VERSION" ] || { echo "AMP_VERSION must be set" >&2; exit 1; }; \
    export AMP_HOME=/opt/amp; \
    export AMP_VERSION; \
    curl -fsSL https://ampcode.com/install.sh | bash; \
    test -x /opt/amp/bin/amp; \
    reported="$(/opt/amp/bin/amp --version)"; \
    echo "amp --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $1}')"; \
    [ "$installed" = "$AMP_VERSION" ] || { \
      echo "pin mismatch: descriptor says $AMP_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

# The staged tree: the install prefix and one shim, nothing under /home.
#
# The shim is a symlink in /usr/local/bin rather than a PATH export in
# /etc/profile.d: /usr/local/bin is on PATH on every base and in every kind of
# shell, while a profile.d file is only read by a login shell -- and `sbx
# exec` and an agent's own subprocesses are not that. v2 declared no
# environment.variables, so there is no env file to write beside it either.
#
# Ownership is explicit rather than inherited from the install: everything
# here is root's, which is what /opt and /usr/local/bin are on any base.
# Numeric because `scratch` carries no /etc/passwd for a name to resolve
# against.
RUN set -eux; \
    mkdir -p /out/opt /out/usr/local/bin; \
    cp -a /opt/amp /out/opt/amp; \
    chown -R 0:0 /out/opt /out/usr/local/bin; \
    ln -s /opt/amp/bin/amp /out/usr/local/bin/amp

# NOTE on self-update: the CLI's own updater writes to the AMP_HOME it
# resolves at run time, which -- with the variable deliberately unexported --
# is the user's ~/.amp, not this prefix. On a base whose PATH puts
# ~/.local/bin ahead of /usr/local/bin (the sandbox templates do) an updated
# copy wins; otherwise the shim keeps pointing at the version this kit built.
# The workload installs into the agent's home and has no such seam.

# The overlay: the install prefix and its shim, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays, and the user runs
# `amp` from the shell, passing `--dangerously-allow-all` themselves if they
# want the workload kit's behavior.
FROM scratch
COPY --from=build /out /
