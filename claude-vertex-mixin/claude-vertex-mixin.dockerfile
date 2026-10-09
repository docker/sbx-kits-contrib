# syntax=docker/dockerfile:1

# Overlay recipe for the claude-vertex mixin. The payload is one environment
# variable. A mixin's image ENV does not become the composed image's, so it also
# rides as a profile.d export, sourced by the base workload's login shell.
#
# The build stage needs a shell to write the file; scratch has none.
FROM docker/sandbox-templates:claude-code-docker AS build

USER root
RUN mkdir -p /out/etc/profile.d \
 && printf '%s\n' 'export CLAUDE_CODE_USE_VERTEX=1' \
      > /out/etc/profile.d/claude-vertex-env.sh

FROM scratch
ENV CLAUDE_CODE_USE_VERTEX=1
COPY --from=build /out /
