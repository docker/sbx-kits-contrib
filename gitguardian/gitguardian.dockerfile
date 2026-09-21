# syntax=docker/dockerfile:1
# ggshield as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: it did not, until now. A v2 mixin had no content
# mechanism -- a lifecycle install hook was the only way for one to install
# anything -- so ggshield arrived from a hook at every sandbox create, and the
# first v3 cut transcribed that faithfully. v3 lets a mixin carry an overlay,
# and this download belongs in one: a version- and SHA256-pinned release
# tarball is pure content, reading nothing that exists only at sandbox-create
# time.
#
# What moving it buys: no per-create download of a ~100 MB PyInstaller bundle,
# a digest fixed in a published layer that can be scanned rather than
# re-verified in every sandbox, a withdrawn release failing the build at
# publish instead of failing a user's sandbox creation, and -- the one visible
# in the permission surface -- all three GitHub hosts gone from
# gitguardian.yaml's network policy, which no longer has an install phase at
# all. That grant existed for this download and nothing else.
#
# WHAT STAYED A HOOK, in gitguardian.yaml: `ggshield machine setup --agent
# claude-code`, which registers the scanner in Claude Code's own
# ~/.claude/settings.json. That is the case an overlay cannot express however
# convenient it would be. The file belongs to the composed claude base, which
# writes it too, and a layer *replaces* a file rather than merging into it --
# shipping a settings.json here would silently discard whatever the agent kit
# put there. Registration is an append to somebody else's file, which is
# create-time work by nature. It also writes under /home/agent, which on the
# composed base may be a mounted volume.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN, handed in by the frontend from the descriptor's `version` arg
# (buildArg: GGSHIELD_VERSION), which gitguardian.yaml also expands into
# `provides` and into its own `version:` -- so the release is stated in exactly
# one place.
#
# No default, deliberately: the descriptor always supplies one, and an empty
# fallback would build a nonsense URL rather than failing. The guard below
# fails instead.
#
# The per-arch SHA256s stay beside it, carried over from the install hook
# unchanged, and they are what makes an installer-supplied `version` safe: a
# different release fails the digest check rather than installing quietly
# under a descriptor still publishing this number. Bumping ggshield is the
# three-part edit the README documents -- the arg's default in
# gitguardian.yaml and both digests here, together -- each digest being the
# sha256sum of the release tarball.
ARG GGSHIELD_VERSION
ARG TARGETARCH

USER root

# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- which is also why gitguardian.yaml no longer
# requires `deb/dpkg`: nothing left in the sandbox asks dpkg anything. The
# per-arch slug mapping is unchanged, since GitHub's asset names use the target
# triple rather than either vocabulary.
#
# The release is a self-contained PyInstaller bundle -- a launcher beside an
# _internal/ tree it resolves relative to itself -- so the whole directory is
# staged under /opt and a symlink puts the launcher on PATH. Not a copy of the
# launcher: that would be a program without its payload.
#
# /opt/ggshield is the same path the install hook used, and keeping it is not
# merely continuity. `ggshield machine setup` resolves its own executable and
# writes that absolute path into Claude Code's settings.json, so the hook
# commands a sandbox ends up with read `/opt/ggshield/ggshield ...` -- moving
# the tree would move what the agent's own configuration points at.
#
# `chown -R 0:0` on the staged tree. A release tarball records whatever uid
# the publisher's machine had and `tar -x` carries it in -- the sibling mise
# kit's archive arrives as 1001:1001, a CI runner -- which is harmless in a
# build stage but not as image content on an unknown base, where that id may
# be a real account and a file's owner can rewrite it whatever its mode says.
# GitGuardian's archive happens to be root-owned today (checked: all 2536
# entries), so this asserts the invariant rather than repairing a known
# breach, and it costs one line to stop depending on a publisher's CI
# configuration. Root is what a root-run install leaves anyway, and the agent
# needs to run this tree, not write to it.
RUN set -eu; \
    [ -n "${GGSHIELD_VERSION}" ] || { echo "GGSHIELD_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) \
        slug="x86_64-unknown-linux-gnu"; \
        sha256=234d1a62ea7b769695c7e5aee8f29e9d0069cd09b4e5b67493d3b529abb44e4a ;; \
      arm64) \
        slug="aarch64-unknown-linux-gnu"; \
        sha256=097616513fe7a4f25831a464b8968b124af32d274e2ce006e388800605696b20 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    dirname="ggshield-${GGSHIELD_VERSION}-${slug}"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/ggshield.tgz \
      "https://github.com/GitGuardian/ggshield/releases/download/v${GGSHIELD_VERSION}/${dirname}.tar.gz"; \
    echo "${sha256}  /tmp/ggshield.tgz" | sha256sum -c -; \
    mkdir -p /out/opt /out/usr/local/bin; \
    tar -C /out/opt -xzf /tmp/ggshield.tgz; \
    mv "/out/opt/${dirname}" /out/opt/ggshield; \
    rm -f /tmp/ggshield.tgz; \
    chown -R 0:0 /out/opt; \
    ln -s /opt/ggshield/ggshield /out/usr/local/bin/ggshield

# THE GATE. The hook ended with a bare `ggshield --version`, which proved the
# binary starts; this compares what it prints against the pin as well, because
# the descriptor now publishes `ggshield@<the version arg>` and an overlay
# whose content disagreed with its own provide is the one failure worse than
# floating.
#
# It runs the staged launcher at its real path rather than the symlink, which
# points at /opt/ggshield -- where the tree will live on the composed base, not
# where it sits in this stage. That absolute link is correct for the overlay
# and unresolvable here, which is precisely the reason a build cannot prove a
# symlink: only composing the overlay onto a base and running the tool can, and
# the README records that run.
#
# The reported line is split into fields and one is required to equal the pin
# exactly, rather than tested as a substring -- `1.53.0` is a substring of
# `11.53.01`. ggshield prints `ggshield, version 1.53.0`, so the comma is a
# field separator here. The emptiness guard is repeated because `grep -Fxq ""`
# matches every line, so an unset pin would turn this gate into an
# unconditional pass, which is the one way a verification step is worse than
# none.
#
# The output is captured whole and trimmed afterwards rather than piped into
# `head`, so that `set -e` sees the tool's own exit status rather than head's
# -- a binary that prints its version and then fails should not pass a gate
# whose job is to prove the content works. It also avoids killing a chatty
# tool with SIGPIPE, which is what the sibling mise recipe hit.
RUN <<'EOF'
set -eu
[ -n "${GGSHIELD_VERSION}" ] || { echo "GGSHIELD_VERSION must be set" >&2; exit 1; }
out="$(/out/opt/ggshield/ggshield --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "ggshield --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${GGSHIELD_VERSION}" || {
  echo "pin mismatch: descriptor says ${GGSHIELD_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF

# WHAT THIS OVERLAY CANNOT CARRY, and so what the composed base must provide:
# a glibc userland. The release this kit pins is the `-unknown-linux-gnu`
# build, and a PyInstaller bundle brings its own Python and its own extension
# modules but still links the host's libc. That was equally true of the install
# hook; it is only stated here because content makes the dependency the kit's
# rather than the sandbox's. Verified by composing this overlay onto a bare
# ubuntu:24.04 and running the tool -- see the README.
#
# The overlay: the bundle under /opt and one symlink, landing on any base.
# Nothing under /home -- /opt and /usr/local are what a mixin landing on an
# unknown base should prefer, since whatever is at /home/agent may be a mounted
# volume, and the one thing this kit does write there stays a hook for exactly
# that reason. No ENTRYPOINT -- the base workload's launch command stays, and
# the agent's own hooks invoke `ggshield`.
FROM scratch
COPY --from=build /out /
