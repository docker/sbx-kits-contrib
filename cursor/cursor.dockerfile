# syntax=docker/dockerfile:1

# Content recipe for the `cursor` workload kit — the v2 Dockerfile, renamed to
# the companion stem the v3 frontend looks for (cursor.yaml -> cursor.dockerfile)
# and grown the two stanzas that used to live in spec.yaml: v2's
# `environment.variables` and `sandbox.entrypoint`. A v3 workload's layers are
# the root filesystem and its image config is the runtime contract, so the
# descriptor declares neither.
#
# v2's `sandbox.image: docker.io/sbx/cursor-image:latest` named the image CI
# built from this file and published separately. In v3 there is one artifact:
# this recipe's output *is* the kit, so the reference is gone rather than moved.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Cursor Agent has no interactive-auth wrapper to install (unlike kiro's
# device-flow launcher) — the sandbox proxy resolves the `cursor` credential
# the descriptor declares and injects it per request. So all this layer has to
# do is put the agent on disk.
#
# It installs into /home/agent/.local/bin/cursor-agent. That path is what the
# ENTRYPOINT below names, in full: the directory is on this image's PATH, but
# the runtime owns PATH and the entrypoint is exec'd rather than run through a
# login shell, so the kit does not rely on the lookup succeeding.
#
# WHY THIS NO LONGER PIPES https://cursor.com/install INTO BASH. The kit's
# `version` arg pins the release, and that installer cannot be pinned: it
# takes no version argument and no version environment variable, and the
# endpoint ignores query parameters — `?version=` and `?v=` both return the
# current script unchanged. The release identifier is baked into the script
# body when the vendor generates it. Piping it while the descriptor published
# `cursor@${{ kit.args.version }}` would assert a version the content need not
# have, which is worse than floating.
#
# So the layer does what the script does, with the version as a parameter. The
# script is short and its install step is entirely mechanical — the whole of it
# is reproduced here:
#
#   1. map uname to the vendor's arch spelling (x86_64 -> x64, aarch64 ->
#      arm64). TARGETARCH is the build's own answer to the same question, and
#      is what makes a cross-build fetch the right tarball rather than the
#      builder's.
#   2. fetch https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz
#      and untar it with --strip-components=1 into
#      ~/.local/share/cursor-agent/versions/<version>/. (The script extracts to
#      a .tmp- directory and renames, for atomicity against a half-written
#      install in a real home directory. A build layer is atomic already:
#      either the RUN succeeds and the layer exists, or it does not.)
#   3. symlink both names the script creates — `agent`, the primary, and
#      `cursor-agent`, which it labels legacy and which this kit's ENTRYPOINT
#      names — into ~/.local/bin.
#
# Two departures from the vendor's one-liner survive the change, both about
# failing closed rather than open:
#
#   - `-L`. `-f` does not treat a 3xx as an error, so without `-L` a redirect
#     would leave tar reading an empty body, and `pipefail` is what turns that
#     into a failed build rather than an image with no agent in it.
#   - the assertion afterwards. A completed install proves an exit code, not an
#     installed binary — so the binary is executed, and its reported version is
#     compared against the pin. `cursor-agent --version` prints the identifier
#     bare, on one line, which is exactly the string in the URL above: that
#     round trip is what makes `provides: ["cursor@..."]` a checked claim.
ARG CURSOR_VERSION
ARG TARGETARCH
RUN <<EOF
set -exo pipefail
[ -n "${CURSOR_VERSION}" ] || { echo "CURSOR_VERSION must be set" >&2; exit 1; }

case "${TARGETARCH}" in
  amd64) arch=x64 ;;
  arm64) arch=arm64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

dir="/home/agent/.local/share/cursor-agent/versions/${CURSOR_VERSION}"
mkdir -p "$dir" /home/agent/.local/bin
curl -fsSL "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/$arch/agent-cli-package.tar.gz" \
  | tar --strip-components=1 -xzf - -C "$dir"

ln -sfn "$dir/cursor-agent" /home/agent/.local/bin/agent
ln -sfn "$dir/cursor-agent" /home/agent/.local/bin/cursor-agent

test -x /home/agent/.local/bin/cursor-agent
installed=$(/home/agent/.local/bin/cursor-agent --version)
[ "$installed" = "${CURSOR_VERSION}" ] || {
  echo "installed cursor-agent $installed != pinned ${CURSOR_VERSION}" >&2; exit 1; }
EOF

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting it
# over a base with no Docker engine yields a sandbox started in Docker mode with
# nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine is
# really present rather than trusting this label.
#
# It stays a label rather than becoming a capability: v3 has no
# Docker-in-Docker capability type, and inventing one would be a declaration no
# runtime answers.
LABEL com.docker.sandboxes.start-docker="true"

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier — it surfaces the value
# as an image's `Agent` in the API, and separately uses it (with any `-docker`
# suffix trimmed) to warn when a template looks built for a different agent than
# the one being run. So it must be the kit's own name: `cursor`.
LABEL com.docker.sandboxes.flavor="cursor"

# Informational only — nothing in sbx reads this. Worth setting because the base
# is a floating tag rebuilt nightly, so this is the one place the produced image
# records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here — nothing reads it, and this image
# is not part of that template family, so it is left alone rather than asserted.

# v2's environment.variables, in the slot OCI already owns for static env.
#
# AGENT_CLI_CREDENTIAL_STORE keeps Cursor's credentials in memory only. Left
# unset, Cursor reads its file-backed store (~/.config/cursor/auth.json),
# JWT-validates what it finds, fails on the proxy sentinel, and re-prompts for
# login — which is exactly the prompt a resolved credential is supposed to
# remove. With the store in memory the sentinel arrives through the agent's
# auth-token environment variable instead and is never validated locally.
ENV IS_SANDBOX=1 \
    AGENT_CLI_CREDENTIAL_STORE=memory

# v2's sandbox.entrypoint. Absolute path on purpose: the vendor installer drops
# cursor-agent into ~/.local/bin, which is on this image's PATH but is not
# something a kit should lean on — the runtime owns PATH and may replace it, and
# the launch is an exec of this argv rather than a login shell.
#
# --yolo makes cursor-agent run tools without asking for per-tool approval. That
# is the point of a sandbox — the blast radius is the container — and it matches
# how this agent has always started under sbx. It does NOT bypass the separate
# workspace-trust gate; see the descriptor's pre-trust install hook.
#
# MIGRATION NOTE: this replaces v2's `CMD ["/home/agent/.local/bin/cursor-agent"]`.
# That CMD existed so a bare `docker run` of the separately-published base image
# started the agent without --yolo, keeping its own approval prompts; now that
# the descriptor's launch command lives in the image config, a surviving CMD
# would be appended to this argv as a stray path argument.
ENTRYPOINT ["/home/agent/.local/bin/cursor-agent", "--yolo"]
