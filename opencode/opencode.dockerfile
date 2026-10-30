# syntax=docker/dockerfile:1

# Content for the `opencode` workload kit.
#
# One image, no flavour suffix: the kit is its own content, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a kit carries a single root filesystem, so a second image would be
# unreachable without a second kit to consume it.
#
# MIGRATION NOTE: this was v2's Dockerfile, built by CI into
# docker.io/sbx/opencode-image:latest and named back from spec.yaml's
# `sandbox.image`. In v3 the recipe is the kit's content directly, so the
# published-tag round trip is gone. The base is v2's default, verbatim.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker.io/sbx/shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# The kit's `version` arg arriving as a build arg -- opencode.yaml declares it
# with `buildArg: OPENCODE_VERSION`, validates its shape, and expands the same
# value into `provides: ["opencode@..."]`. Deliberately no default here: the
# descriptor is the single source of the pin, and a second default in this file
# would be one more thing to keep in sync with it. Move the pin with
# `--build-arg version=1.2.3` (npm semver, no leading "v"), which moves the
# install and the provide together.
ARG OPENCODE_VERSION

# The official v2 installer downloads and extracts the platform binary directly
# from the npm registry. It selects the architecture, libc and x86 AVX2 variant
# itself, without requiring npm or Node at image build time.
#
# `--no-modify-path` keeps the installer from changing shell startup files. The
# image owns PATH directly, which also makes the binary available to exec'd
# processes that never read a shell rc file.
ENV PATH="/home/agent/.opencode/bin:${PATH}"

# Download before executing so a failed transfer cannot be mistaken for a
# successful empty shell script. `opencode --version` proves the binary is on
# the image PATH, not merely that the installer exited successfully.
RUN <<EOF
set -eux

curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install
if [ -n "${OPENCODE_VERSION:-}" ]; then
  bash /tmp/opencode-install --version "${OPENCODE_VERSION}" --no-modify-path
else
  bash /tmp/opencode-install --no-modify-path
fi
rm -f /tmp/opencode-install

opencode --version
EOF

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# MIGRATION NOTE: this stays a label. It is not a v3 capability -- the grammar
# has no Docker-in-Docker request, and `privileged@1` is a different (larger)
# ask that this kit never made.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell", and sbx would report
# this image's agent as "shell".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `opencode`.
LABEL com.docker.sandboxes.flavor="opencode"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here -- nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# v2's sandbox.entrypoint: bare `opencode`, no flags — the launch the agent this
# kit replaces used. There is no "skip approvals" flag to add here as there is
# for the other agent kits in this repo: OpenCode's approval behaviour is
# configured in opencode.json or through OPENCODE_PERMISSION, not on the command
# line.
#
# MIGRATION NOTE: v2's `CMD ["opencode"]` is dropped rather than kept beside
# it -- the launch argv is Entrypoint + Cmd (SPEC-v3 §8), so leaving the CMD in
# place would run `opencode opencode`.
ENTRYPOINT ["opencode"]
