# syntax=docker/dockerfile:1

# Overlay recipe for the claude-sbx-statusline mixin: one script, at the path
# Claude Code's `statusLine` key points at.
#
# MIGRATION NOTE: v2 shipped this through the kit's `files/` tree, where
# `files/home/<rel>` was packed into a layer and written to `/home/agent/<rel>` at
# create time. v3 has no `files/` convention — a mixin's layers ARE its content —
# so the same tree is staged into the overlay and arrives with the image instead of
# being written per sandbox. The source file is kept in place at
# `files/home/.claude/statusline.sh` so the mapping stays legible.
#
# A build stage rather than a bare `FROM scratch` + `COPY`, for one specific
# reason: an overlay's directory entries override the base's, and the parent
# directories a COPY creates are root-owned. A root-owned /home/agent landing on
# the composed image would take $HOME away from the agent user. So the stage
# creates the tree explicitly and sets ownership per level — /home stays root's, as
# it is in any ordinary image, and /home/agent and its .claude are the agent's.
# Numeric ids because that is what the platform floor fixes (uid/gid 1000).
FROM docker/sandbox-templates:shell-docker AS build

COPY files/home/.claude/statusline.sh /tmp/statusline.sh

USER root
RUN set -eux; \
    mkdir -p /out/home/agent/.claude; \
    install -m 0755 -o 1000 -g 1000 /tmp/statusline.sh /out/home/agent/.claude/statusline.sh; \
    chown 1000:1000 /out/home/agent /out/home/agent/.claude

# The overlay: one script, landing on any base.
FROM scratch
COPY --from=build /out /
