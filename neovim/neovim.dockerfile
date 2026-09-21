# syntax=docker/dockerfile:1
# An overlay, not a root filesystem: Neovim itself, the bundled ~/.config/nvim
# and the kit's exports, landing on any base.
#
# WHAT CHANGED HERE, and it is the whole reason this file has two build stages:
# Neovim used to be installed by a lifecycle hook at sandbox create, because a
# v2 mixin had no content mechanism and this recipe therefore only carried the
# static files. v3 lets a mixin carry an overlay, and the download is a pinned
# artifact fetch with nothing create-time in it, so it builds here now. That
# buys no per-create download, a release fixed in a scannable published layer,
# a bad release surfacing as a red build rather than a failed sandbox creation
# in front of a user, and the disappearance of the kit's entire install-phase
# network grant -- the three GitHub hosts existed only so that hook could reach
# them. Nothing stayed a hook; see neovim.yaml.
#
# The download needs a glibc userland with curl, a CA store and a shell that can
# run the downloaded binary to check its version, so it gets the template base
# every other baked overlay in this repo uses. The static-file assembly keeps
# busybox, which is all it ever needed. The two stages stage into their own
# /out and the scratch stage copies both, so each keeps the ownership it set.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS fetch

# THE PIN, reaching this recipe the ordinary way at last. neovim.yaml's
# `version` arg carries `buildArg: NVIM_VERSION`, so the frontend hands this
# build `--build-arg NVIM_VERSION=<pin>`; the same value expands into
# `provides` and into the descriptor's own `version:`. Before the install
# moved, the arg was declared here and unused -- its value reached the install
# by being expanded into the *hook body's* download URL instead, which is why
# neovim.yaml carried a long note explaining a build arg on a kit that built
# nothing. That note is now just the ordinary wiring.
#
# No default, deliberately: the descriptor always supplies one, and a fallback
# here would be a second place for the version to live and drift. An empty
# value fails the guard below rather than fetching something unintended.
ARG NVIM_VERSION
ARG TARGETARCH

USER root

# v2's install hook, moved here.
#
# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- and asking dpkg is what made the kit require
# `deb/dpkg` of every base it composed onto, a requirement that goes with it.
# The case arms keep the dpkg vocabulary because TARGETARCH speaks it too.
#
# The layout is the hook's, unchanged: the tarball's own arch-named directory
# under /opt, with a stable /usr/local/bin/nvim symlink into it. Both ends of
# that link are in this overlay, which is what keeps it from being the dangling
# link an overlay usually ships when an installer relocates a launcher -- it is
# also why the kit's verification composes the overlay and runs nvim rather
# than trusting this stage's own `nvim --version`.
RUN set -eu; \
    [ -n "${NVIM_VERSION}" ] || { echo "NVIM_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) tarball="nvim-linux-x86_64.tar.gz"; nvim_dir="nvim-linux-x86_64" ;; \
      arm64) tarball="nvim-linux-arm64.tar.gz";  nvim_dir="nvim-linux-arm64"  ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL \
      "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/${tarball}" \
      -o /tmp/nvim.tar.gz; \
    mkdir -p /out/opt /out/usr/local/bin; \
    tar -C /out/opt -xzf /tmp/nvim.tar.gz; \
    rm /tmp/nvim.tar.gz; \
    ln -sf "/opt/${nvim_dir}/bin/nvim" /out/usr/local/bin/nvim; \
    # The release tarball records the publisher's CI uid, and tar preserves it:
    # as image content on an unknown base that id may be a real account, and a
    # file's owner can rewrite it whatever its mode says. /opt and
    # /usr/local/bin are root on any base, so root is also what they should be
    # here -- numeric, because `scratch` carries no /etc/passwd for a name to
    # resolve against.
    chown -R 0:0 /out/opt /out/usr/local/bin; \
    # The pin's own check, and the reason the provide can be trusted: what is
    # asserted is the release tarball's payload, not the tag it was filed
    # under. `nvim --version` opens with the `NVIM v<version>` banner, so an
    # asset renamed, re-cut or served from a redirect that landed elsewhere
    # fails the build rather than publishing a layer that answers to
    # `neovim@<declared>` while carrying something else. This ran in the hook
    # before, which meant the same mismatch failed sandbox creation instead.
    banner="$("/out/opt/${nvim_dir}/bin/nvim" --version | head -1)"; \
    echo "nvim --version: ${banner}"; \
    case "${banner}" in \
      *"v${NVIM_VERSION}"*) ;; \
      *) echo "pin mismatch: kit declares ${NVIM_VERSION}, nvim reports '${banner}'" >&2; exit 1 ;; \
    esac

# The assembly stage for the kit's static content. It is here to own the result
# precisely: BuildKit applies a COPY --chown to every parent directory it
# creates, so copying straight into a scratch stage would hand /home itself to
# the agent. Staging under /out and chowning only the agent's own subtree
# leaves /home as the base has it, which is what v2's create-time copy into an
# existing tree did.
FROM busybox:1.37 AS build

# v2's `files/home/` tree, landing where the v2 convention put it:
# /home/agent/<relative path>. Chowned by number — busybox has no `agent` user,
# and uid/gid 1000 is the platform floor's agent. This is the one thing the kit
# ships under the agent's home, and it has to be there: it is nvim's config
# path.
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# MIGRATION NOTE: v2's `environment.variables` land here. A mixin has no
# `environment:` slot in v3 and its image config is not the composed image's,
# so the variables ride the overlay as a profile.d snippet the base's login
# shell sources.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/neovim-env.sh <<'EOF'
export EDITOR=nvim
export VISUAL=nvim
EOF

# The overlay: the pinned Neovim release, the bundled nvim config and the kit's
# exports, on any base. Two sources because the two stages own different
# ownership: /opt and /usr/local/bin are root, /home/agent is uid 1000, and
# each stage set its own before the copy. No ENTRYPOINT -- the base workload's
# launch command stays.
FROM scratch
COPY --from=fetch /out /
COPY --from=build /out /
