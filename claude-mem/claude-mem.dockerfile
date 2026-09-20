# syntax=docker/dockerfile:1

# Overlay recipe for the claude-mem mixin.
#
# The kit installs itself from npm in a lifecycle hook, so the overlay carries no
# software at all — only the three environment variables the v2 kit declared.
#
# MIGRATION NOTE: v3 has no static-env grammar for a mixin. A mixin's image config
# does not become the composed image's, so `environment.variables` becomes a
# profile.d drop-in sourced by the base workload's login shell. The build stage is
# the claude family's own base (a shell is needed to write the file; `scratch` has
# none).
FROM docker/sandbox-templates:shell-docker AS build

# CLAUDE_MEM_TELEMETRY is scoped to claude-mem on purpose. The cross-tool
# DO_NOT_TRACK convention would also silence the base claude kit and anything
# else in the sandbox, which is not this mixin's call to make. Upstream's consent
# ladder is DO_NOT_TRACK > CLAUDE_MEM_TELEMETRY > config > default-on, so this
# alone turns claude-mem's PostHog telemetry off; `us.i.posthog.com` is also
# absent from the descriptor's allow-list, which holds even if upstream renames
# the variable.
#
# CLAUDE_MEM_WORKER_PORT is pinned because the worker port otherwise defaults to
# 37700 + (uid % 100), which would shift if the base image's agent uid ever
# changed — and the descriptor's port@1 entry names 37700.
#
# CLAUDE_MEM_WORKER_HOST overrides upstream's 127.0.0.1 default, which is
# unreachable through `sbx ports --publish`: the worker must bind eth0/0.0.0.0 to
# be forwarded.
USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' \
      'export CLAUDE_MEM_TELEMETRY=0' \
      'export CLAUDE_MEM_WORKER_PORT=37700' \
      'export CLAUDE_MEM_WORKER_HOST=0.0.0.0' \
      > /out/etc/profile.d/claude-mem-env.sh

# The overlay: three exports, landing on any base.
FROM scratch
COPY --from=build /out /
