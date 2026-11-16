# syntax=docker/dockerfile:1
# The mise CLI as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: it did not, until now. A v2 mixin had no content
# mechanism -- a lifecycle install hook was the only way for one to install
# anything, and for a mixin to set static environment at all -- so all three of
# this kit's jobs were create-time hooks, and the first v3 cut transcribed them
# faithfully. v3 lets a mixin carry an overlay, and two of the three belong in
# one:
#
#   * The mise binary. A version- and SHA256-pinned release tarball is pure
#     content, reading nothing that exists only at sandbox-create time.
#   * The /etc/profile.d export. A static file with a constant in it, written
#     by root into a path no other kit claims. The v3 migration guide
#     prescribes exactly this location for a mixin's static environment,
#     because a mixin's image config is not the composed image's; a hook that
#     writes it at create was only ever standing in for the layer this kit did
#     not have.
#
# What moving them buys: no per-create download, a digest fixed in a published
# layer that can be scanned rather than re-verified in every sandbox, a
# withdrawn release failing the build at publish instead of failing a user's
# sandbox creation, and -- the one visible in the permission surface --
# github.com and the two asset hosts gone from mise.yaml's INSTALL phase,
# which no longer exists. They remain in `runtime`, and that is not a
# contradiction: the `ubi` backend fetches from the same hosts when the agent
# later runs `mise install`, which is the user's traffic and genuinely
# in-sandbox.
#
# WHAT STAYED A HOOK, in mise.yaml: the `~/.bashrc` append that runs
# `mise activate bash`. A layer REPLACES a file rather than merging into it, so
# shipping a .bashrc here would discard whatever the composed workload put in
# its own -- and this kit needs one line added to that file, not the file. It
# is also under /home/agent, which on the composed base may be a mounted
# volume. That is why this kit ships a profile.d drop and a bashrc hook rather
# than picking one: the two reach different shells, and only one of them is
# a file this kit may own outright.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN, handed in by the frontend from the descriptor's `version` arg
# (buildArg: MISE_VERSION), which mise.yaml also expands into `provides` and
# into its own `version:` -- so the release is stated in exactly one place.
#
# No default, deliberately: the descriptor always supplies one, and an empty
# fallback would build a nonsense URL rather than failing. The guard below
# fails instead.
#
# The per-arch SHA256s stay beside it, carried over from the install hook
# unchanged, and they are what makes an installer-supplied `version` safe: a
# different release fails the digest check rather than installing quietly
# under a descriptor still publishing this number. Bumping mise is the
# three-part edit the README documents -- the arg's default in mise.yaml and
# both digests here, together -- with the checksums from the release's
# SHASUMS256.txt.
ARG MISE_VERSION
ARG TARGETARCH

USER root

# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- which is also why mise.yaml no longer requires
# `deb/dpkg`: nothing left in the sandbox asks dpkg anything.
#
# The arch is mapped rather than interpolated, because mise does not use the
# dpkg vocabulary on both arms: its amd64 asset is spelled `x64`. The hook got
# this right by accident of the same case statement; keeping the mapping
# explicit is what stops a future arch being pasted in wrong.
#
# Only `mise/bin/mise` is extracted, as the hook did. The archive also carries
# a man page, a fish activation snippet, a LICENSE and a `mise.d`; an overlay
# should land what it means to land rather than whatever an archive happens to
# hold, and none of those are on any path this kit claims.
#
# `install -o 0 -g 0` rather than a plain copy, and here it is repairing a real
# breach rather than asserting an invariant: every one of the 13 entries in
# this tarball is owned by 1001:1001, the uid of the CI runner that built the
# release. Harmless in a build stage; as image content on an unknown base that
# id may be a real account, and a file's owner can rewrite it whatever its mode
# says.
RUN set -eu; \
    [ -n "${MISE_VERSION}" ] || { echo "MISE_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) \
        slug="x64"; \
        sha256=cdf616b3d8554bece574cb1a5c0f19cc0f551dffbecf66037df1cc06569a42ef ;; \
      arm64) \
        slug="arm64"; \
        sha256=a746ad85fe8a7b62a6c72939da5fb4231074fd16c482f6334a598bd92926f41e ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/mise.tgz \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${slug}.tar.gz"; \
    echo "${sha256}  /tmp/mise.tgz" | sha256sum -c -; \
    tar -C /tmp -xzf /tmp/mise.tgz mise/bin/mise; \
    mkdir -p /out/usr/local/bin; \
    install -m 0755 -o 0 -g 0 /tmp/mise/bin/mise /out/usr/local/bin/mise; \
    rm -rf /tmp/mise /tmp/mise.tgz

# THE GATE. The hook ended with a bare `mise --version`, which proved the
# binary starts; this compares what it prints against the pin as well, because
# the descriptor now publishes `mise@<the version arg>` and an overlay whose
# content disagreed with its own provide is the one failure worse than
# floating.
#
# The reported line is split into fields and one is required to equal the pin
# exactly, rather than tested as a substring -- `2026.5.2` is a substring of
# `12026.5.21`. The emptiness guard is repeated because `grep -Fxq ""` matches
# every line, so an unset pin would turn this gate into an unconditional pass,
# which is the one way a verification step is worse than none.
#
# The output is captured whole and trimmed afterwards rather than piped into
# `head`: mise writes more than one line here, and closing the pipe under it
# made it die on SIGPIPE and print `Aborted` into the build log. Capturing
# first also means `set -e` sees the tool's own exit status instead of head's,
# so a binary that starts, prints its version and then fails no longer passes
# this gate.
RUN <<'EOF'
set -eu
[ -n "${MISE_VERSION}" ] || { echo "MISE_VERSION must be set" >&2; exit 1; }
out="$(/out/usr/local/bin/mise --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "mise --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${MISE_VERSION}" || {
  echo "pin mismatch: descriptor says ${MISE_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF

# v2's `environment.variables`, and then the hook that stood in for it.
#
# A mixin's image config is not the composed image's (SPEC-v3 §10), so this
# cannot be an ENV and the migration guide prescribes a profile.d drop, which
# the base workload's login shell sources. The v3 cut wrote that file from a
# root install hook purely because the kit had no recipe to put it in; the
# file, its comment and its value are carried over here verbatim.
#
# Unlike the ~/.bashrc line, this file is one this kit may own outright: the
# name is the kit's, no other kit or base writes it, and so replacing rather
# than merging is the correct semantics rather than a hazard.
#
# The same export is repeated in the ~/.bashrc snippet the remaining hook
# writes, deliberately: profile.d reaches login shells while ~/.bashrc reaches
# the interactive non-login shells mise activation is actually wired into, and
# an unset value there is a trust prompt -- the one thing this variable exists
# to prevent.
RUN <<'EOF'
set -eu
mkdir -p /out/etc/profile.d
cat > /out/etc/profile.d/mise-env.sh <<'SCRIPT'
# Treat the whole sandbox filesystem as trusted so `.mise.toml` files don't trigger an
# interactive trust prompt. This is appropriate inside a sandbox: the user has already
# opted into running this code by attaching the workspace.
export MISE_TRUSTED_CONFIG_PATHS="/"
SCRIPT
chmod 0644 /out/etc/profile.d/mise-env.sh
chown -R 0:0 /out/etc
EOF

# WHAT THIS OVERLAY CANNOT CARRY, and what the composed base must therefore
# provide: a system CA store. mise builds its HTTP client eagerly and unwraps
# the result, so with no trust store it panics before doing anything at all --
# `mise --version` prints the version and then dies with "No CA certificates
# were loaded from the system" and exit 101. It does that even with networking
# disabled, so it is the store's absence and not a failed request.
#
# This is inside SPEC-v3 §12's platform floor, which guarantees a CA store, so
# no sandbox base is affected and the kit declares nothing for it. It is
# recorded because it is what a bare `ubuntu:24.04` shows and the workload's
# own base hides: verified by composing this overlay onto ubuntu:24.04, where
# mise panics, and onto ubuntu:24.04 plus ca-certificates, where it reports
# the pinned release and exits 0.
#
# The overlay: one pinned binary and one profile.d snippet, landing on any
# base. Nothing under /home -- /usr/local and /etc/profile.d are what a mixin
# landing on an unknown base should prefer, since whatever is at /home/agent
# may be a mounted volume, and the one thing this kit does write there stays a
# hook for exactly that reason. No ENTRYPOINT -- the base workload's launch
# command stays, and the agent runs `mise` from the shell.
FROM scratch
COPY --from=build /out /
