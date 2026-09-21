# syntax=docker/dockerfile:1

# Content recipe for the `droid` kit — the v2 Dockerfile, renamed to the
# stem droid.dockerfile so the descriptor beside it finds it without a
# `dockerfile:` field.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a workload kit's layers are the one root filesystem, so a second
# image would be unreachable without a second kit to consume it.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Supplied by the descriptor's `version` arg, which owns the default and the
# accepted shape. No default here on purpose: the descriptor expands this same
# value into a versioned provide, so an unset value has to fail the build
# rather than silently install something.
ARG DROID_VERSION

# Droid CLI has no interactive-auth wrapper to install (unlike kiro's
# device-flow launcher) — the sandbox proxy injects FACTORY_API_KEY (or
# resolves the credential's OAuth block) per the credential capability in
# droid.yaml. So all this has to do is put the binary on PATH.
#
# It used to do that with the upstream one-liner, `curl -fsSL
# https://app.factory.ai/cli | sh`, verbatim from
# https://docs.factory.ai/cli/getting-started/quickstart. That installer takes
# no version — `VER="0.223.0"` is a plain literal, and the script reads neither
# `$@` nor the environment — so piping it could never produce the pinned
# install the descriptor's provide claims. What it does publish is a versioned
# artifact layout, in its own URL lines:
#
#     URL="$BASE_URL/factory-cli/releases/$VER/$platform/$droid_architecture/$binary_name"
#     SHA_URL="$BASE_URL/factory-cli/releases/$VER/$platform/$droid_architecture/$binary_name.sha256"
#
# So the block below is that script's download step with $VER replaced by the
# kit's arg: the same host, the same path template, the same published
# checksum, the same install location. Everything else the installer does is
# not wanted here — it pkills running droids, and it prints shell-rc advice for
# a PATH that is already configured on this base.
RUN <<EOF
set -exo pipefail

test -n "${DROID_VERSION}" || { echo "DROID_VERSION is empty; pass the kit's version arg" >&2; exit 1; }

# Transcribed from the installer's own detection, uname for uname: under
# buildx, uname reports the TARGET architecture, so this selects the right
# artifact for a cross-built image.
case "$(uname -m)" in
    x86_64|amd64)  arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Also the installer's: Factory ships a second x64 build for CPUs without
# AVX2, and only for x64. Carried across rather than dropped, so the artifact
# this build selects is the one the floating install would have selected.
#
# It reads the BUILDER's /proc/cpuinfo, which is a pre-existing wart of running
# any CPU-probing installer inside a build — the image can outlive the machine
# that built it. Faithfulness wins over fixing it here: a grammar-and-pin
# change is not the place to alter which binary the kit ships.
if [ "$arch" = "x64" ] && ! grep -qi avx2 /proc/cpuinfo 2>/dev/null; then
    arch="x64-baseline"
fi

base="https://downloads.factory.ai/factory-cli/releases/${DROID_VERSION}/linux/$arch"

# ~/.local/bin, the installer's own DST. It is on PATH on this base, which is
# what lets the ENTRYPOINT below stay a bare `droid`.
mkdir -p "$HOME/.local/bin"
curl -fsSL -o "$HOME/.local/bin/droid" "$base/droid"

# The vendor's published checksum for this exact version, which is what makes
# bypassing the installer lose nothing: `curl | sh` verified the same digest
# from the same origin. The file holds the bare hex, so the filename is
# supplied here.
printf '%s  %s\n' "$(curl -fsSL "$base/droid.sha256")" "$HOME/.local/bin/droid" | sha256sum -c -
chmod +x "$HOME/.local/bin/droid"

# The build-time gate. A completed RUN proves an exit code, not a working
# binary — and the descriptor publishes `droid@${DROID_VERSION}` as a provide,
# so a download that quietly served a different release would make that claim
# false. -F because a version is dots, not a regexp; -w so a declared 0.22.3
# cannot be satisfied by an installed 0.22.31.
droid --version
droid --version | grep -Fw "${DROID_VERSION}"
EOF

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# It stays a label rather than becoming a v3 capability: `privileged@1` is a
# different, larger ask, and the v2 kit never declared it.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `droid`.
LABEL com.docker.sandboxes.flavor="droid"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# v2's `sandbox.entrypoint: [droid]`, in the slot OCI already owns for launch
# config — the v3 descriptor carries none. This replaces the v2 file's
# `CMD ["droid"]` rather than joining it: the launch argv is Entrypoint + Cmd,
# so keeping both would run `droid droid`.
ENTRYPOINT ["droid"]
