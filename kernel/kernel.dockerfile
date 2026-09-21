# syntax=docker/dockerfile:1
# An overlay, not a root filesystem: two build stages stage their output under
# /out, and a final `FROM scratch` stage copies those trees to `/`, so the result
# lands on whatever base the composition puts underneath it.
#
# The assembly stages are here to own the result precisely: BuildKit applies a
# COPY --chown to every parent directory it creates, so copying straight into a
# scratch stage would hand /home itself to the agent. Staging under /out and
# chowning only the agent's own subtree leaves /home as the base has it.
#
# WHAT MOVED HERE AND WHY: the Kernel CLI used to arrive from a lifecycle install
# hook (`npm install -g @onkernel/cli`, uid 0, at sandbox create). Under v2 a
# mixin had no content mechanism at all, so a hook was the only way for this kit
# to install anything; v3 lets a mixin carry an overlay, so the install is pure
# build-time content and belongs here. Nothing about it reads sandbox-create
# state -- no create-phase arg, no WORKSPACE_DIR, no credential mode, no in-
# sandbox Docker daemon -- and no kit declares a volume over the paths it writes,
# so nothing would mount over what is baked. Moving it means no per-create npm
# latency, a digest-pinned and scannable CLI, a broken install that fails at
# publish instead of in a user's sandbox, and -- the real payoff -- the kit's
# install-phase network grant disappears entirely: npm and the two GitHub
# release-asset hosts were needed by this hook and nothing else, so the
# descriptor's `install:` phase and its whole `lifecycle@1` capability are gone.
#
# AND NOW PINNED, which the move alone was not. Relocating the install changed
# only *when* `latest` was resolved -- once per publish rather than once per
# sandbox -- and left the descriptor publishing `kernel@1.0.0`, the kit's own
# release number wearing the CLI's name. The install takes an exact version from
# the descriptor's `version` arg instead, and the build asks the installed binary
# what it is; see the RUN below.

# ---------------------------------------------------------------------------
# The static quick-reference guide. Kept on its own minimal base, unchanged from
# the migration: it needs a shell and `chown` and nothing else.
# ---------------------------------------------------------------------------
FROM busybox:1.37 AS guide

# v2's `files/home/` tree, landing where the v2 convention put it:
# /home/agent/<relative path>, so the guide stays at the
# /home/agent/.kernel/quickstart.md path kernel-context.md points the agent at.
# Chowned by number — busybox has no `agent` user, and uid/gid 1000 is the
# platform floor's agent.
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# ---------------------------------------------------------------------------
# The Kernel CLI. The install is run unmodified on a base that carries node and
# npm, then the specific resulting paths are copied out -- the shape the authoring
# guide prescribes for an install with no relocation flag. `npm install -g` has
# no prefix indirection that would let it target /out directly, and
# @onkernel/cli's postinstall writes the downloaded binary inside its own package
# tree, so relocating after the fact would break the bin symlink's relative path.
# Everything is therefore preserved at the absolute path it was built at.
# ---------------------------------------------------------------------------
FROM docker/sandbox-templates:shell-docker AS cli

USER root

# THE PIN. The kit's `version` arg arrives as this build arg: kernel.yaml
# validates its shape and expands the same value into `provides` and into its own
# `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an empty
# fallback would install `@onkernel/cli@` -- which npm reads as the latest
# dist-tag -- while the descriptor went on asserting a number. A missing value
# fails the build instead; see the guard below.
ARG KERNEL_VERSION

# @onkernel/cli's postinstall (install.js, GoReleaser-generated) downloads the
# actual kernel binary from a GitHub release asset, so this step needs egress to
# registry.npmjs.org, github.com and the release-asset redirect target. At create
# time that came from the descriptor's install-phase allow list; at build time it
# comes from the builder's ordinary network, which is why that allow list is no
# longer needed at all.
#
# The version spec is exact -- `@onkernel/cli@0.39.3`, never a range or a
# dist-tag -- so what npm resolves is what the descriptor promised.
#
# The comparison afterwards is what makes the provide trustworthy rather than
# merely requested: the descriptor publishes `kernel@${KERNEL_VERSION}`, so an
# install that produced something else would ship an overlay whose provide lies
# about its own content -- the one failure mode worse than floating. It also
# closes a gap npm leaves open here specifically: the version npm resolves is the
# *package's*, while the binary the postinstall then downloads from a GitHub
# release is what actually runs, so the two could disagree without npm noticing.
# `kernel --version` prints `kernel <version> (<commit>) <go version> <date>`, so
# the second field is the number to match, read through the global prefix rather
# than through PATH because that prefix is not on every base's.
RUN set -eux; \
    [ -n "$KERNEL_VERSION" ] || { echo "KERNEL_VERSION must be set" >&2; exit 1; }; \
    npm install -g "@onkernel/cli@${KERNEL_VERSION}"; \
    reported="$("$(npm prefix -g)/bin/kernel" --version)"; \
    echo "kernel --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $2}')"; \
    [ "$installed" = "$KERNEL_VERSION" ] || { \
      echo "pin mismatch: descriptor says $KERNEL_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

RUN <<'EOF'
set -eux

# Asked for rather than hardcoded, so a future base that moves the global prefix
# fails this build instead of producing an overlay that silently contains
# nothing. On the template bases NPM_CONFIG_PREFIX is /usr/local/share/npm-global,
# which is not on every base's PATH -- hence the /usr/local/bin symlink below.
prefix="$(npm prefix -g)"
root="$(npm root -g)"

# Fail loudly rather than shipping an empty overlay. Both halves are asserted
# because they move independently: the package tree (which holds the
# postinstall-downloaded binary) and npm's bin symlink into it.
test -d "$root/@onkernel/cli"
test -e "$prefix/bin/kernel"

mkdir -p "/out${prefix}/bin" "/out${root}/@onkernel" /out/usr/local/bin

cp -a "$root/@onkernel/cli" "/out${root}/@onkernel/cli"
# Travels as the relative symlink npm created ($prefix/bin/kernel ->
# ../lib/node_modules/@onkernel/cli/...), which resolves because the tree above
# is preserved at its absolute path.
cp -a "$prefix/bin/kernel" "/out${prefix}/bin/kernel"

# An overlay's directory entries override the base's, so every directory this
# overlay ships has to reproduce the ownership the base gives it. The template
# bases own the whole global prefix as agent:agent so the agent can `npm install
# -g` without sudo -- the README tells the agent to do exactly that for the SDK --
# and only the prefix root exists on a bare base: npm created bin/, lib/ and
# lib/node_modules/ in this stage, as root. Shipping them root-owned would quietly
# take that away, so all four are set from the one directory the base does own,
# read from the real base rather than hardcoded.
chown --reference="$prefix" \
  "/out${prefix}" "/out${prefix}/bin" "/out${prefix}/lib" "/out${root}"

# The package tree is this kit's own content, and it is normalized rather than
# shipped with the ownership `cp -a` preserved. That ownership is not the base's
# and not the agent's: npm replays the publisher's recorded uid for tarballs
# predating its ownership normalization (501:20 on several transitive deps here),
# and @onkernel/cli's postinstall extracts a GoReleaser archive built in CI, which
# carries its runner's uid (1001:1001 on the 20MB binary). A create-time install
# hook landed those same ids, but an overlay ships them as image content onto an
# *unknown* base, where they may be real accounts -- and a file's owner can
# rewrite it whatever its mode says, which for the CLI's own binary and the
# JavaScript it loads is worth closing. Root-owned with world read+traverse is the
# conventional ownership for software under /usr/local and makes the layer's
# ownership deterministic instead of inherited from whoever published what.
# Removing the CLI is unaffected: that depends on node_modules/, which stays the
# agent's above.
chown -R 0:0 "/out${root}/@onkernel"
chmod -R a+rX "/out${root}/@onkernel"

# /usr/local/bin/kernel, which is what the README documents and what every base
# has on PATH. Not redundant with npm's own bin entry above: $prefix/bin is only
# on PATH because *this* base puts it there, and an overlay lands on a base that
# may not. Absolute, because a copy of npm's relative link would resolve against
# /usr/local/lib from here.
ln -sf "$prefix/bin/kernel" /out/usr/local/bin/kernel
EOF

# The overlay: the CLI and the quick-reference guide, on any base.
FROM scratch
COPY --from=cli /out /
COPY --from=guide /out /
