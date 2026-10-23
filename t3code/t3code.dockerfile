# syntax=docker/dockerfile:1
# T3 Code's pinned `t3` release as an overlay, in the layout its remote
# bootstrap consumes.
#
# The release is pure content: downloading, verifying and unpacking it reads
# nothing that exists only at sandbox-create time, so it is built once here
# instead of once per sandbox, and no sandbox downloads ~85 MB at create. The
# archive is self-contained (no Node.js, prebuilt native modules, node-pty
# among them), so no compiler is involved. The one thing its binaries need that
# the templates lack is libatomic1, and apt cannot travel in an overlay: the
# descriptor's install hook adds it in the sandbox, and this stage adds it only
# so the `t3 --version` gate below can run.
#
# The base is the image family the kit documents as its target, so the gate
# proves the binary runs against the libc the sandbox will have.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN. The kit's `version` arg arrives as this build arg: t3code.yaml
# validates its shape and expands the same value into `provides`, its own
# `version:` field and the install hook that links the bootstrap's path here.
#
# No default here, deliberately. The descriptor always supplies one, and an
# empty fallback would build a URL naming no release. A missing value fails the
# build instead; see the guard below.
ARG T3_VERSION
# Set per platform by buildx, so `--platform linux/amd64,linux/arm64` resolves
# each leg to its own archive. t3 names the amd64 build `x64`.
ARG TARGETARCH

USER root

# Only so the gate below can start the binary; it never reaches the overlay.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends libatomic1; \
    rm -rf /var/lib/apt/lists/*

# THE INSTALL T3 Code's bootstrap would otherwise do on first connection, done
# the same way: fetch SHA256SUMS and the archive for this architecture from the
# release, verify the archive against its line, unpack it with
# --strip-components=1 into runtime/versions/<version>/, gate, then write the
# .install-complete marker holding the version and a newline.
#
# Unpacked straight to its final path, /opt/t3code/runtime/versions/<version>,
# so the gate runs the binary exactly where the overlay puts it. The tree is
# relocatable (the bootstrap installs it under whatever $HOME is), which is what
# lets it live at /opt and be reached through the hook's symlink. Nothing goes
# under /home: whatever is at /home/agent on the composed base may be a mounted
# volume that covers the overlay at create.
#
# THE GATE. `t3 --version` proves the binary runs on this architecture and
# libc, and comparing what it prints against the pin is what makes the provide
# trustworthy rather than merely requested: the descriptor publishes
# `t3@${T3_VERSION}`, so an archive reporting something else would ship an
# overlay whose provide lies about its own content. It prints `t3 v<version>`;
# the descriptor's value carries no `v` because SPEC-v3 §5.2 admits no prefix.
# Exact rather than a substring match on purpose: if upstream changes the format
# this should fail loudly and be re-read, not quietly keep passing.
RUN set -eu; \
    [ -n "${T3_VERSION:-}" ] || { echo "T3_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH:-}" in \
      amd64) t3_arch=x64 ;; \
      arm64) t3_arch=arm64 ;; \
      *) echo "t3 publishes no Linux release for TARGETARCH '${TARGETARCH:-}' (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    archive="t3-${T3_VERSION}-linux-${t3_arch}.tar.gz"; \
    base_url="https://github.com/pingdotgg/t3code/releases/download/v${T3_VERSION}"; \
    staging="$(mktemp -d)"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o "${staging}/SHA256SUMS" "${base_url}/SHA256SUMS"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o "${staging}/${archive}" "${base_url}/${archive}"; \
    expected="$(awk -v f="${archive}" '$2 == f || $2 == "*" f { print $1 }' "${staging}/SHA256SUMS")"; \
    [ -n "${expected}" ] || { echo "SHA256SUMS for v${T3_VERSION} has no line for ${archive}" >&2; exit 1; }; \
    echo "${expected}  ${staging}/${archive}" | sha256sum -c -; \
    dir="/opt/t3code/runtime/versions/${T3_VERSION}"; \
    mkdir -p "${dir}"; \
    tar -xzf "${staging}/${archive}" -C "${dir}" --strip-components=1 --no-same-owner; \
    rm -rf "${staging}"; \
    reported="$("${dir}/t3" --version)"; \
    echo "t3 --version: ${reported}"; \
    [ "${reported}" = "t3 v${T3_VERSION}" ] || { \
      echo "pin mismatch: descriptor says ${T3_VERSION}, binary reports '${reported}'" >&2; \
      exit 1; \
    }; \
    printf '%s\n' "${T3_VERSION}" > "${dir}/.install-complete"

# The staged tree: the runtime directory and nothing else.
#
# Ownership is explicit rather than inherited from the archive: root, which is
# what /opt is on any base, and numeric because `scratch` carries no /etc/passwd
# for a name to resolve against. Root-owned and not group- or world-writable is
# all t3 needs: it only reads and executes this tree and writes its state
# under the user's ~/.t3, beside it.
RUN set -eux; \
    mkdir -p /out/opt; \
    cp -a /opt/t3code /out/opt/t3code; \
    chown -R 0:0 /out/opt; \
    chmod -R a+rX,go-w /out/opt

# WHAT THIS OVERLAY CANNOT CARRY:
#
#   - libatomic1. The release's binaries link it, no sandbox template ships it
#     (checked with ldconfig on docker/sandbox-templates:shell-docker), and an
#     overlay cannot carry dpkg state. t3code.yaml's install hook adds it
#     before the agent starts.
#   - The bootstrap's own path, ~/.t3/runtime/versions/<version>. It lives under
#     /home, which the overlay stays out of; the descriptor's second install
#     hook links it to /opt/t3code/runtime/versions/<version> as the agent user.
#
# The overlay lands on any base. No ENTRYPOINT -- the base workload's launch
# command stays, and T3 Code's SSH bootstrap starts `t3`.
FROM scratch
COPY --from=build /out /
