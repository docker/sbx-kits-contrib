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

# Pin a release by passing --build-arg OPENCODE_VERSION=1.2.3 (npm semver, no
# leading "v"). Left empty, the build installs the newest published version.
ARG OPENCODE_VERSION=""

# OpenCode is installed from npm rather than through the standalone
# `curl https://opencode.ai/install | bash` script its README leads with. Both
# are first-party and release in lockstep, and the npm route is what suits an
# image build:
#
#   - It resolves nothing through the unauthenticated GitHub releases API, so a
#     busy shared runner's rate limit cannot fail the build.
#   - The binary lands in the npm global prefix, which the base image already
#     exports on PATH. The standalone installer instead drops the binary in
#     ~/.opencode/bin and appends a PATH line to a shell rc file, which an
#     exec'd container process never reads — so that route needs PATH or
#     symlink repair here that this one does not.
#   - It needs no host the kit does not already have to allow: OpenCode
#     resolves language servers, plugins and provider SDK packages from
#     registry.npmjs.org at run time regardless of how it was installed.
#
# It also leaves `opencode upgrade` resolving new versions from npm, which is
# the same host and the same agent-writable prefix, so in-place self-update
# keeps working.
#
# Two things the install line has to get right:
#
#   - The published package's bin/opencode.exe is a stub; its postinstall
#     script replaces it with the platform binary it selects from the package's
#     optional dependencies, matching architecture, libc and (on x86) AVX2
#     support. A corepack-managed npm shim does not run lifecycle scripts, so
#     installing through one would ship the stub and still exit 0. Disabling
#     the shim first is therefore a correctness step, not tidying — and it is
#     allowed to fail: on a base whose npm is a distro binary rather than a
#     corepack shim there is nothing to disable and nothing to remove.
#   - `--include=optional` restates npm's own default so an inherited
#     `omit=optional` — from an .npmrc or from NPM_CONFIG_OMIT — cannot leave
#     the postinstall with no binary to copy.
#
# `opencode --version` last, deliberately: the install's exit code says only
# that npm ran, not that a working binary reached PATH. The npm cache is
# dropped in the same layer because it holds a second copy of a ~180 MB
# tarball that nothing reads again.
RUN <<EOF
set -eux

(corepack disable npm 2>&1 || echo "no corepack npm shim to disable")

npm install -g "opencode-ai@${OPENCODE_VERSION:-latest}" --include=optional

opencode --version

npm cache clean --force
rm -rf "${HOME}/.npm"
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
