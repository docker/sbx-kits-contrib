# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv

# Overlay recipe for the claude-openrouter mixin: the two fixed variables, as a
# profile.d export for login shells and as image ENV so they also reach the
# entrypoint process. Only this kit sets them, so the env merge cannot conflict.
# The model variables are create args in claude-openrouter.yaml instead.
#
# ANTHROPIC_AUTH_TOKEN is a placeholder; the proxy replaces it with the real
# key. The lint skip above is for that name, not for a secret.
#
# The build stage is a real base because writing a file needs a shell and
# `scratch` has none.
FROM docker/sandbox-templates:shell-docker AS build

USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' \
      'export ANTHROPIC_BASE_URL=https://openrouter.ai/api' \
      'export ANTHROPIC_AUTH_TOKEN=proxy-managed' \
      > /out/etc/profile.d/claude-openrouter-env.sh

FROM scratch
ENV ANTHROPIC_BASE_URL=https://openrouter.ai/api
ENV ANTHROPIC_AUTH_TOKEN=proxy-managed
COPY --from=build /out /
