# syntax=docker/dockerfile:1
# A mixin is an overlay, not a root filesystem. This one carries no files:
# its only image content is the additive environment config below.
FROM scratch

# Host-side endpoint policy allow-lists agent processes carrying this marker.
# Any agent process that spawns without it is denied at the endpoint.
# SANDBOX_ENFORCEMENT_MARKER is create-specific, so the descriptor's markerId
# arg exports it through `env:` rather than baking one caller's value here.
ENV SANDBOX_ENFORCED="1"
