# syntax=docker/dockerfile:1

# Base image for the `opencode` sandbox kit.
#
# One image, no flavour suffix: the kit picks its own image, so the
# Docker-in-Docker detail never reaches the user. There is no dockerless variant
# either — a kind:sandbox kit names a single sandbox.image, so a second image
# would be unreachable without a second kit to consume it.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Pin a release by passing --build-arg OPENCODE_VERSION=1.2.3. Left empty, the
# official installer resolves the newest published version.
ARG OPENCODE_VERSION=""

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
if [ -n "${OPENCODE_VERSION}" ]; then
  bash /tmp/opencode-install --version "${OPENCODE_VERSION}" --no-modify-path
else
  bash /tmp/opencode-install --no-modify-path
fi
rm -f /tmp/opencode-install

opencode --version
jq --version
EOF

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
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
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

CMD [ "opencode" ]
