# syntax=docker/dockerfile:1

# Overlay recipe for the claude-ollama mixin.
#
# The kit's whole payload is one environment variable and one wrapper script, and
# the wrapper is a lifecycle `files:` entry shared with the workload shape — so
# all the overlay carries is the variable.
#
# MIGRATION NOTE: the workload sets CLAUDE_OLLAMA_MODEL as image ENV. A mixin
# cannot — its image config is not the composed image's — so it rides here as a
# profile.d export, sourced by the base workload's login shell, which is the same
# shell the user runs `claude-ollama` from.
#
# The build stage is the workload's own base (the v2 `sandbox.image`, carried
# over verbatim) because writing a file needs a shell and `scratch` has none.
FROM docker/sandbox-templates:claude-code-docker AS build

USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' 'export CLAUDE_OLLAMA_MODEL=gemma4:e4b-it-q4_K_M' \
      > /out/etc/profile.d/claude-ollama-env.sh

# The overlay: one export, landing on any base. No ENTRYPOINT — the base
# workload's launch command stays and the user runs `claude-ollama`.
FROM scratch
COPY --from=build /out /
