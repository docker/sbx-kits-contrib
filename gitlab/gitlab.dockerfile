# syntax=docker/dockerfile:1
# The GitLab CLI as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: it did not, until now. A v2 mixin had no content
# mechanism -- a lifecycle install hook was the only way for one to install
# anything -- so `glab` arrived from a hook at every sandbox create, and the
# first v3 cut transcribed that faithfully. v3 lets a mixin carry an overlay,
# and this download belongs in one: a version- and SHA256-pinned release
# tarball is pure content, reading nothing that exists only at sandbox-create
# time.
#
# What moving it buys: no per-create download, a digest fixed in a published
# layer that can be scanned rather than re-verified in every sandbox, a
# withdrawn release failing the build at publish instead of failing a user's
# sandbox creation, and -- the one visible in the permission surface --
# gitlab.com gone from gitlab.yaml's network policy, which no longer has an
# install phase at all. That grant existed for this download and nothing else.
#
# WHAT STAYED A HOOK, in gitlab.yaml: seeding glab's own config with a `hosts:`
# entry for the target instance. The instance comes from the kit's create-phase
# `host` arg, so it has no value here; the hook also refuses to clobber a
# config a user has since edited, which is a decision about state that already
# exists in a sandbox -- something a layer cannot make, because a layer
# replaces a file rather than looking at it. It writes under /home/agent
# besides, which on the composed base may be a mounted volume.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN, handed in by the frontend from the descriptor's `version` arg
# (buildArg: GLAB_VERSION), which gitlab.yaml also expands into `provides` and
# into its own `version:` -- so the release is stated in exactly one place.
#
# No default, deliberately: the descriptor always supplies one, and an empty
# fallback would build a nonsense URL rather than failing. The guard below
# fails instead.
#
# The per-arch SHA256s stay beside it, carried over from the install hook
# unchanged, and they are what makes an installer-supplied `version` safe: a
# different release fails the digest check rather than installing quietly
# under a descriptor still publishing this number. Bumping glab is the
# three-part edit the README documents -- the arg's default in gitlab.yaml and
# both digests here, together -- with the checksums from the release's
# checksums.txt.
ARG GLAB_VERSION
ARG TARGETARCH

USER root

# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- which is also why gitlab.yaml no longer requires
# `deb/dpkg`: nothing left in the sandbox asks dpkg anything. GitLab spells its
# assets in the same amd64/arm64 vocabulary, so the tarball name is unchanged.
#
# Only `bin/glab` is extracted, as the hook did: the archive also carries docs
# and completions this kit has never shipped, and an overlay should land what
# it means to land rather than whatever an archive happens to hold.
#
# `install -o 0 -g 0` rather than a plain copy of the extracted file. A release
# tarball records the publisher's own uid and `tar -x` carries it in; harmless
# in a build stage, but as image content on an unknown base that id may be a
# real account, and a file's owner can rewrite it whatever its mode says.
RUN set -eu; \
    [ -n "${GLAB_VERSION}" ] || { echo "GLAB_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) \
        sha256=f3782ddb62b6ab20d0031699ea7b43f345dc6f63e991883660e21343b9524931 ;; \
      arm64) \
        sha256=0f6171766dd7f8246b7ce85bab18bd99d57ce2538e0ec9121c48fe004308eac4 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    tarball="glab_${GLAB_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/glab.tgz \
      "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/${tarball}"; \
    echo "${sha256}  /tmp/glab.tgz" | sha256sum -c -; \
    tar -C /tmp -xzf /tmp/glab.tgz bin/glab; \
    mkdir -p /out/usr/local/bin; \
    install -m 0755 -o 0 -g 0 /tmp/bin/glab /out/usr/local/bin/glab; \
    rm -rf /tmp/glab.tgz /tmp/bin

# THE GATE. The hook ended with a bare `glab --version`, which proved the
# binary starts; this compares what it prints against the pin as well, because
# the descriptor now publishes `glab@<the version arg>` and an overlay whose
# content disagreed with its own provide is the one failure worse than
# floating.
#
# The reported line is split into fields and one is required to equal the pin
# exactly, rather than tested as a substring -- `1.118.0` is a substring of
# `11.118.01`, and glab's label wording is not this kit's to depend on. The
# emptiness guard is repeated because `grep -Fxq ""` matches every line, so an
# unset pin would turn this gate into an unconditional pass, which is the one
# way a verification step is worse than none.
#
# The output is captured whole and trimmed afterwards rather than piped into
# `head`, so that `set -e` sees the tool's own exit status rather than head's
# -- a binary that prints its version and then fails should not pass a gate
# whose job is to prove the content works. It also avoids killing a chatty
# tool with SIGPIPE, which is what the sibling mise recipe hit.
RUN <<'EOF'
set -eu
[ -n "${GLAB_VERSION}" ] || { echo "GLAB_VERSION must be set" >&2; exit 1; }
out="$(/out/usr/local/bin/glab --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "glab --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${GLAB_VERSION}" || {
  echo "pin mismatch: descriptor says ${GLAB_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF

# The overlay: one pinned binary, landing on any base. Nothing under /home --
# /usr/local is what a mixin landing on an unknown base should prefer, since
# whatever is at /home/agent may be a mounted volume, and the one thing this
# kit does write there stays a hook for exactly that reason.
#
# No /etc/profile.d drop either, and that is not an omission: the kit's one
# static export, GITLAB_HOST, is the `host` arg's own value and reaches the
# container through `env: GITLAB_HOST` on the arg. A profile.d script here
# would have to bake one instance into the published layer, which is the
# opposite of what that arg is for.
#
# No ENTRYPOINT -- the base workload's launch command stays, and the agent runs
# `glab` from the shell.
FROM scratch
COPY --from=build /out /
