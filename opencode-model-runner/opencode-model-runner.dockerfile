# syntax=docker/dockerfile:1
# Content for the `opencode-model-runner` workload kit.
#
# The v2 kit shipped no Dockerfile: it named this published template in
# `sandbox.image` and declared the entrypoint beside it. This image reference
# is that value carried over verbatim. A v3 workload's layers are the root
# filesystem, so the recipe says the same thing the v2 pair did, in the slot
# the image config already owns.
#
# Nothing is installed on top: this kit's whole substance is the provider
# config its lifecycle `files:` entry writes, which is a declaration rather
# than content, and OpenCode fetches the discovery plugin itself at startup.
FROM docker/sandbox-templates:opencode-docker

# The one thing this recipe does beyond naming the base: hold the base to the
# OpenCode release the descriptor's provide publishes.
#
# There is no install here to pin, so the kit's `version` arg arrives as an
# expectation rather than a selector -- hence the name. `opencode --version`
# prints a bare version string, and comparing it is what turns
# `provides: ["opencode-model-runner@<version>"]` from a claim about the
# content into a fact verified against it. Without this gate the declared
# version would drift silently the next time Docker rebuilds
# `:opencode-docker`, and the kit would publish a version it does not carry.
#
# Failing here is the intended behavior, not an outage: the fix is to read the
# new version out of the message and bump `args.version.default` in
# opencode-model-runner.yaml, in lockstep with ../opencode-model-runner-mixin,
# which asserts the same value against the same template.
#
# Runs as the base's own `agent` user -- no USER line, so the image config's
# identity is untouched -- and adds no content, only an empty layer.
ARG EXPECTED_OPENCODE_VERSION
RUN <<'EOF'
set -eu
actual="$(opencode --version)"
if [ "${actual}" != "${EXPECTED_OPENCODE_VERSION}" ]; then
  echo "opencode-model-runner: base image ships OpenCode ${actual}, but this" >&2
  echo "kit declares ${EXPECTED_OPENCODE_VERSION} and publishes it as the" >&2
  echo "version of its provide. Bump args.version.default in" >&2
  echo "opencode-model-runner.yaml (and in the -mixin kit) to ${actual}." >&2
  exit 1
fi
EOF

# v2's sandbox.entrypoint. There was no `environment.variables` block to carry.
ENTRYPOINT ["opencode"]
