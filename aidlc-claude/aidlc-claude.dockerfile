# syntax=docker/dockerfile:1

# Overlay recipe for the aidlc-claude mixin: the two merge scripts the startup
# hook runs under Bun.
#
# MIGRATION NOTE: v2 shipped these through the kit's `files/` tree, where
# `files/home/<rel>` was packed into a layer and written to `/home/agent/<rel>` at
# create time. v3 has no `files/` convention — a mixin's layers ARE its content —
# so the same tree is staged into the overlay and arrives with the image instead of
# being written per sandbox. The sources are kept in place under
# `files/home/.local/lib/` so the mapping stays legible.
#
# Bun itself is NOT here: it is installed by an install hook, pinned to a release
# tag, into /usr/local/bin. That stays a hook rather than moving into this overlay
# because the hook is also what the kit's README documents and what sets
# BUN_INSTALL — the one detail that keeps the binary out of /root/.bun.
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
RUN set -eux; \
    mkdir -p /out/home/agent/.local/lib; \
    install -m 0644 -o 1000 -g 1000 /tmp/lib/aidlc-merge-settings.ts /tmp/lib/aidlc-merge-gitignore.ts \
      /out/home/agent/.local/lib/; \
    chown 1000:1000 /out/home/agent /out/home/agent/.local /out/home/agent/.local/lib

# The overlay: two scripts, landing on any base.
FROM scratch
COPY --from=build /out /
