# syntax=docker/dockerfile:1
# Overlay recipe for the droid mixin.
#
# Factory's install is user-scoped: the CLI lands under $HOME/.local and
# nothing offers a --prefix to redirect it at, so the shape the guide
# prescribes for an unrelocatable install applies — run the same install the
# workload runs on the workload's own base, then copy the specific resulting
# paths into a scratch overlay.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so the absolute paths are already correct when the overlay lands. Installing
# under a staging HOME and moving the tree afterwards would leave them
# pointing at a directory that does not exist in the composed sandbox.
FROM docker/sandbox-templates:shell-docker AS build

# Supplied by the descriptor's `version` arg, which owns the default and the
# accepted shape. No default here on purpose: the descriptor expands this same
# value into a versioned provide, so an unset value has to fail the build
# rather than silently install something.
ARG DROID_VERSION

USER root
# Ownership is scoped to /out/home/agent, not /out: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent && chown -R agent:agent /out/home/agent

USER agent
ENV HOME=/home/agent
# The same install the workload does, and for the same reason it is spelled
# out rather than piped from https://app.factory.ai/cli: that installer takes
# no version — `VER="0.223.0"` is a plain literal and the script reads neither
# `$@` nor the environment — so piping it could never produce the pinned
# install the descriptor's provide claims. Its own URL lines,
#
#     URL="$BASE_URL/factory-cli/releases/$VER/$platform/$droid_architecture/$binary_name"
#     SHA_URL="$BASE_URL/factory-cli/releases/$VER/$platform/$droid_architecture/$binary_name.sha256"
#
# are a versioned layout, so the block below is that download step with $VER
# replaced by the kit's arg: same host, same path template, same published
# checksum, same install location. Keep it in step with ../droid.
RUN <<EOF
set -eux

test -n "${DROID_VERSION}" || { echo "DROID_VERSION is empty; pass the kit's version arg" >&2; exit 1; }

# Transcribed from the installer's own detection, uname for uname: under
# buildx, uname reports the TARGET architecture.
case "$(uname -m)" in
    x86_64|amd64)  arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Also the installer's: Factory ships a second x64 build for CPUs without
# AVX2, and only for x64. Carried across rather than dropped, so this overlay
# selects the artifact the floating install would have selected. It reads the
# BUILDER's /proc/cpuinfo, a pre-existing wart of running any CPU-probing
# installer inside a build; faithfulness to ../droid wins over fixing it here.
if [ "$arch" = "x64" ] && ! grep -qi avx2 /proc/cpuinfo 2>/dev/null; then
    arch="x64-baseline"
fi

base="https://downloads.factory.ai/factory-cli/releases/${DROID_VERSION}/linux/$arch"

# ~/.local/bin, the installer's own DST, and the path the copy-out below
# expects. Nothing here symlinks onto PATH — the overlay does that itself with
# the /usr/local/bin shim further down, which is why the installer's own
# PATH-advice tail is not wanted.
mkdir -p "$HOME/.local/bin"
curl -fsSL -o "$HOME/.local/bin/droid" "$base/droid"

# The vendor's published checksum for this exact version, which is what makes
# bypassing the installer lose nothing: `curl | sh` verified the same digest
# from the same origin. The file holds the bare hex, so the filename is
# supplied here.
printf '%s  %s\n' "$(curl -fsSL "$base/droid.sha256")" "$HOME/.local/bin/droid" | sha256sum -c -
chmod +x "$HOME/.local/bin/droid"

# The build-time gate. The descriptor publishes `droid@${DROID_VERSION}` as a
# provide, so a download that quietly served a different release would make
# that claim false. -F because a version is dots, not a regexp; -w so a
# declared 0.22.3 cannot be satisfied by an installed 0.22.31.
"$HOME/.local/bin/droid" --version
"$HOME/.local/bin/droid" --version | grep -Fw "${DROID_VERSION}"
EOF

USER root
# `test -x` pins the assumption that the install lands under ~/.local/bin, so
# a change of layout fails the build here rather than shipping an overlay with
# no agent in it.
RUN set -eux; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    test -x /out/home/agent/.local/bin/droid; \
    mkdir -p /out/usr/local/bin; \
    ln -s /home/agent/.local/bin/droid /out/usr/local/bin/droid

# The bin shim above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them. v2 declared no environment.variables, so there is no env
# file to write beside it.

# The overlay: the agent's install tree and its bin shim, landing on any base.
# No ENTRYPOINT — the base workload's launch command stays, and the user runs
# `droid` from the shell.
FROM scratch
COPY --from=build /out /
