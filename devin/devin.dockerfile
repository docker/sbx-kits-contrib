# syntax=docker/dockerfile:1
# The content of the `devin` workload kit -- the v2 Dockerfile that built
# docker.io/sbx/devin-image:latest, now the kit's own recipe. A v3 workload's
# layers are the root filesystem, so there is no separate published base image
# and no sandbox.image pointing at one.
#
# The build reaches `cli.devin.ai` (install.sh) and `static.devin.ai` (the
# manifest and the versioned bundle the script fetches). Both are also covered
# by the kit's runtime allow list, because `devin update` re-runs the same
# download.
#
# One image, no flavour suffix: the kit is its own content, so the
# Docker-in-Docker detail never reaches the user.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# No version build arg, unlike the sibling kits whose installers document one.
# Cognition's install script takes its target from a manifest it fetches
# itself, and its `PINNED_VERSION` is a literal the script overwrites
# unconditionally, not an environment variable a caller can set -- so a
# DEVIN_VERSION arg would be silently ignored, reading as a pin while pinning
# nothing. That is also why the descriptor declares no `args` and publishes an
# unversioned provide under its own `version:` fallback. Cognition publishes
# per-version setup scripts (`<base>/cli/<version>/setup.sh`); wiring one in
# here is the supported way to pin, if a release needs it. Pin the whole image
# by digest instead, or re-point BASE_IMAGE and install a chosen release by
# hand in the meantime.

# Runs as the base image's default user (`agent`, uid 1000), which matters:
# install.sh is a per-user installer with no --prefix, so everything below
# lands under /home/agent owned by the user that will run it.
RUN <<EOF
set -eux

# `|| true` is not laziness. install.sh ends by running `devin setup`, an
# interactive wizard that cannot complete without a TTY and exits non-zero
# ("Login canceled"). Because that is the script's last command it is also the
# script's exit status, so a clean install reports failure here.
#
# The download is also unauthenticated and unpinned: this build sends no
# credential, and while install.sh does verify the bundle against a sha256
# from the manifest, both come from the same vendor origin -- and the script
# itself is verified by nothing. What arrives is whatever that host serves
# at build time. And `curl | bash` exits 0 whenever curl dies after
# producing some output, so a truncated response is indistinguishable from
# success at this line. That is the other reason the outcome is asserted below
# rather than inferred from a status.
curl -fsSL https://cli.devin.ai/install.sh | bash || true

# ...so assert the outcome instead of trusting the status that was just
# discarded. A genuine download, checksum or unpack failure still fails the
# build here, which is the only thing that makes the `|| true` above safe.
devin --version

# The installer's `devin` is the only one on PATH, and the auth wrapper has to
# take that name for the image's ENTRYPOINT to stay `[devin, ...]`. Expose the
# real CLI as `devin-cli` first.
#
# `readlink` without -f on purpose: it copies the symlink's TARGET rather than
# resolving it all the way to today's version directory, so `devin-cli` keeps
# following the installer's own "current" pointer instead of pinning the
# version installed at build time. devin update moves the "current" pointer,
# so devin-cli follows it. The devin name is this wrapper, a regular file, and
# does not move -- the installer refuses to overwrite a non-symlink at that
# path.
ln -s "$(readlink /home/agent/.local/bin/devin)" /home/agent/.local/bin/devin-cli

# Remove the installer's symlink before the COPY below replaces it. Without
# this, COPY resolves the existing symlink and writes the wrapper THROUGH it,
# overwriting the real CLI binary inside the version directory -- and the
# wrapper would then exec itself.
rm /home/agent/.local/bin/devin
EOF

# The launcher the image's entrypoint resolves as `devin`: it checks
# authentication state, drops into Devin's manual token flow when there is
# none, replaces any real key left on disk with the proxy's placeholder, and
# only then hands off to devin-cli. See the comments in the script itself for
# why each of those steps cannot be expressed declaratively in the descriptor.
COPY --chown=agent:agent --chmod=0755 devin-entrypoint.sh /home/agent/.local/bin/devin

# Inherited from the base image, but re-declared deliberately so the value is
# owned here rather than depending on inheritance from an image this repository
# does not own.
#
# This is a *request* to the runtime, not a description of the image: setting
# it over a base with no Docker engine yields a sandbox started in Docker mode
# with nothing to run. Since BASE_IMAGE is overridable, CI asserts the engine
# is really present rather than trusting this label. It stays a label in v3 --
# it is not a capability.
LABEL com.docker.sandboxes.start-docker="true"

# The image's USER (agent, non-root) is inherited from the base rather than
# re-declared here, and that is on purpose: a re-pointed BASE_IMAGE must still
# land on a non-root `agent` user, or the per-user installer in the RUN block
# above puts the CLI in /root instead of /home/agent and the COPY above writes
# the wrapper somewhere the agent user cannot reach. sbx@1 requires the image
# config to declare a non-empty user, which an inherited USER satisfies --
# Docker carries the base's value into this image's config either way, so the
# requirement is met without pinning a value this kit does not own.

# Both of the labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding is not optional for
# `flavor`: left inherited it would read "shell-docker", and sbx would report
# this image's agent as "shell-docker".
#
# sbx reads `flavor` and treats it as an agent identifier -- it surfaces the
# value as an image's `Agent` in the API, and separately uses it (with any
# `-docker` suffix trimmed) to warn when a template looks built for a different
# agent than the one being run. So it must be the kit's own name: `devin`, not
# `devin-docker`, because only the warning path trims the suffix; the API path
# does not.
LABEL com.docker.sandboxes.flavor="devin"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# Note: `com.docker.sandboxes=templates` also appears on this image. It is
# inherited from the base and is not set here -- nothing reads it, and this
# image is not part of that template family, so it is left alone rather than
# asserted.

# Where the host places the workspace under sbx@1. v2's Dockerfile declared no
# WORKDIR at all and the v2 engine mounted the workspace wherever it chose; in
# v3 the image config is what the host reads, so the kit has to state it. The
# conventional sibling of $HOME keeps the user's checkout off the home
# directory holding ~/.local/bin/devin and ~/.config/devin.
WORKDIR /home/agent/workspace

# MIGRATION NOTE: v2's sandbox.entrypoint, now the image config's -- and v2's
# `CMD [ "devin", … ]`, which existed only so a plain `docker run` of the image
# behaved the way the sandbox did, collapses into it. In v3 there is one
# statement of the launch command and both readings agree by construction.
#
# `devin` here is the auth wrapper installed above, not the CLI itself -- the
# real binary is `devin-cli`. Everything after it is forwarded to the CLI
# verbatim.
#
# --permission-mode dangerous auto-approves every tool call. The container IS
# the sandbox, and a per-tool approval prompt with nobody attached to answer it
# deadlocks the session. The CLI's own rejection message is the authority on
# the accepted values, and it disagrees with the `--help` prose: normal (auto),
# accept-edits, dangerous (yolo, bypass), autonomous (requires --sandbox). So
# `bypass` -- the spelling in the published docs -- is an alias of `dangerous`,
# and `autonomous` is unusable here because it additionally demands the CLI's
# own process sandbox inside the container. An unknown value is rejected at
# parse time rather than ignored, so a typo fails loudly instead of silently
# degrading to prompting.
#
# --respect-workspace-trust defaults to true in every mode, which stops to ask
# before the agent touches an unfamiliar directory. The workspace is the whole
# reason the sandbox exists, so the check is turned off. Spelled with `=`
# deliberately: the flag takes an OPTIONAL value, so the space-separated form
# leaves `false` free to be swallowed as the positional PROMPT argument
# instead.
ENTRYPOINT ["devin", "--permission-mode", "dangerous", "--respect-workspace-trust=false"]
