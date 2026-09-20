# syntax=docker/dockerfile:1

# Overlay recipe for the claude-model-runner mixin.
#
# The whole kit is five environment variables, so that is all the overlay carries.
#
# MIGRATION NOTE: v3 has no static-env grammar for a mixin — a mixin's image
# config does not become the composed image's — so `environment.variables` becomes
# a profile.d drop-in sourced by the base workload's login shell. The build stage
# is the claude family's own base because writing a file needs a shell and
# `scratch` has none.
FROM docker/sandbox-templates:shell-docker AS build

# The descriptor's `model` arg, which is the v3 counterpart of the v2 spec's
# `&model` YAML anchor: declared once, fanned out over all four Claude Code model
# aliases so the default Sonnet/Opus/Haiku/sub-agent picks all hit Docker Model
# Runner. Pass `--build-arg`-style kit args to switch models rather than editing
# this file.
ARG MODEL=gpt-oss

USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' \
      'export ANTHROPIC_BASE_URL=http://host.docker.internal:12434' \
      "export ANTHROPIC_DEFAULT_OPUS_MODEL=${MODEL}" \
      "export ANTHROPIC_DEFAULT_SONNET_MODEL=${MODEL}" \
      "export ANTHROPIC_DEFAULT_HAIKU_MODEL=${MODEL}" \
      "export CLAUDE_CODE_SUBAGENT_MODEL=${MODEL}" \
      > /out/etc/profile.d/claude-model-runner-env.sh

# The overlay: five exports, landing on any base.
FROM scratch
COPY --from=build /out /
