# syntax=docker/dockerfile:1

# Overlay recipe for the claude-bedrock mixin: the two Bedrock variables, as a
# profile.d export for login shells and as image ENV so they also reach the
# entrypoint process. Only this kit sets them, so the env merge cannot conflict.
#
# The build stage is a real base because writing a file needs a shell and
# `scratch` has none.
FROM docker/sandbox-templates:claude-code-docker AS build

USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' \
      'export CLAUDE_CODE_USE_BEDROCK=1' \
      'export ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0' \
      > /out/etc/profile.d/claude-bedrock-env.sh

FROM scratch
ENV CLAUDE_CODE_USE_BEDROCK=1
ENV ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0
COPY --from=build /out /
