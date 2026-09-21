# syntax=docker/dockerfile:1

# Overlay recipe for the aidlc-claude mixin: the pinned Bun runtime, and the two
# merge scripts the startup hook runs under it.
#
# MIGRATION NOTE: v2 shipped the scripts through the kit's `files/` tree, where
# `files/home/<rel>` was packed into a layer and written to `/home/agent/<rel>` at
# create time. v3 has no `files/` convention — a mixin's layers ARE its content —
# so the same tree is staged into the overlay and arrives with the image instead of
# being written per sandbox. The sources are kept in place under
# `files/home/.local/lib/` so the mapping stays legible.
#
# WHAT MOVED HERE AND WHY: Bun used to arrive from a lifecycle install hook that
# ran upstream's installer at sandbox create. Under v2 a mixin had no content
# mechanism at all, so a hook was the only way for this kit to install anything;
# v3 lets a mixin carry an overlay, so a pinned artifact download like this one is
# pure build-time content and belongs here. Nothing about it reads sandbox-create
# state — the version is a literal in this file, not a create-phase arg — and no
# kit in the composition declares a volume over /usr/local/bin, so nothing mounts
# over what is baked. Moving it means no per-create download of a ~35MB runtime,
# a digest-pinned and scannable binary, and a broken install that fails at publish
# rather than in a user's sandbox. It also shrinks the kit's install-phase network
# grant to the one host the remaining hook actually needs: bun.sh and the two
# GitHub release-asset hosts existed for this download and are gone from the
# descriptor.
#
# WHAT DELIBERATELY STAYED A HOOK: the `aidlc-workflows` clone and the harness
# reconcile, for two different reasons. The clone's commit is not a constant — a
# fresh project takes whatever `main` is at create time and records it, and an
# existing project takes the SHA it already pinned in its own workspace — so the
# content is chosen per sandbox and cannot be a layer. The reconcile reads
# `$WORKSPACE_DIR`, which the runtime injects at create and a build cannot know.
# See the descriptor's lifecycle@1 for both.
#
# A build stage rather than a bare `FROM scratch` + `COPY`, for one specific
# reason: an overlay's directory entries override the base's, and the parent
# directories a COPY creates are root-owned. A root-owned /home/agent landing on
# the composed image would take $HOME away from the agent user. So the stage
# creates the tree explicitly and sets ownership per level — /home stays root's, as
# it is in any ordinary image, and everything under /home/agent is the agent's.
# Numeric ids because that is what the platform floor fixes (uid/gid 1000).
FROM docker/sandbox-templates:shell-docker AS build

COPY files/home/.local/lib/ /tmp/lib/

USER root

# Bun, installed exactly as the create-time hook installed it and then copied out,
# rather than pointed at /out directly: the installer's only target knob is
# BUN_INSTALL, and running it against a staging prefix would make this recipe
# depend on Bun being relocatable. The unmodified install into its real prefix is
# the shape the authoring guide prescribes, and `bun --version` here is the same
# assertion the hook made — a failed download now fails the build.
#
# BUN_INSTALL=/usr/local is still the whole fix, for the same reason it was in the
# hook: unset, the installer targets $HOME/.bun, which for a root install means
# /root/.bun — invisible to the agent. /usr/local/bin is already on PATH for every
# user and every shell type, with no rc file involved, which is what the startup
# hook's `bun /home/agent/.local/lib/...` invocation needs. (The installer's own
# PATH wiring is an export appended to ~/.bashrc, which non-interactive shells
# never source, so it would not help even if this ran as the agent.)
#
# Pinned to a release tag rather than plain `| bash`: this kit is tested against
# one Bun version, and the two merge scripts below depend on it. The installer's
# version argument is a release tag (`bun-vX.Y.Z`, per its own usage error), not a
# bare version. This is the pin the hook already carried — moving the install to
# build time neither added it nor loosened it.
RUN set -eux; \
    export BUN_INSTALL=/usr/local; \
    curl -fsSL https://bun.sh/install | bash -s "bun-v1.4.0"; \
    bun --version

RUN set -eux; \
    mkdir -p /out/usr/local/bin; \
    # Both halves asserted before the copy, because they move independently and a
    # missing one is invisible at build time and fatal at run time: the binary, and
    # the bunx symlink beside it that upstream's installer creates.
    test -x /usr/local/bin/bun; \
    test -e /usr/local/bin/bunx; \
    # -a to carry bunx across as the relative symlink it is, which resolves because
    # the binary is preserved at the absolute path it was installed to. Left
    # root-owned and world-executable: /usr/local/bin is root's on any base, and an
    # overlay's directory entries override the base's, so handing it to uid 1000
    # here would give the agent write access to a directory the kit does not own.
    cp -a /usr/local/bin/bun /usr/local/bin/bunx /out/usr/local/bin/

# The two merge scripts the startup hook runs, at the path that hook names.
RUN set -eux; \
    mkdir -p /out/home/agent/.local/lib; \
    install -m 0644 -o 1000 -g 1000 /tmp/lib/aidlc-merge-settings.ts /tmp/lib/aidlc-merge-gitignore.ts \
      /out/home/agent/.local/lib/; \
    chown 1000:1000 /out/home/agent /out/home/agent/.local /out/home/agent/.local/lib

# The overlay: Bun and two scripts, landing on any base.
FROM scratch
COPY --from=build /out /
