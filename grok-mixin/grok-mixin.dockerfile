# syntax=docker/dockerfile:1
# Overlay recipe for the grok mixin.
#
# x.ai's install.sh is an opaque `curl | bash` with a user-scoped prefix: it
# lays the CLI under $HOME and symlinks it onto an existing PATH directory.
# There is no --prefix to redirect it at, so the shape the guide prescribes
# for an unrelocatable install applies — run the unmodified install on the
# workload's own base, then copy the specific resulting paths into a scratch
# overlay.
#
# This is also where the workload's setup hook went: ../grok installs at
# sandbox-create time, this kit installs at image-build time, which is why its
# descriptor declares no install phase and no lifecycle entry.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so the paths the installer bakes are already correct when the overlay lands.
FROM docker/sandbox-templates:shell-docker AS build

# THE PIN. The kit's `version` arg arrives as this build arg: grok-mixin.yaml
# validates its shape and expands the same value into `provides` and into its
# own `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an
# empty fallback is the failure this pin exists to prevent — the install would
# float to whatever the installer's channel pointer currently resolves while the
# descriptor went on asserting a number. A missing value fails the build
# instead; see the guard below.
ARG GROK_VERSION

USER root
# Ownership is scoped to /out/home/agent, not /out: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent && chown -R agent:agent /out/home/agent

USER agent
ENV HOME=/home/agent
# ~/.local/bin is pre-created because the installer will symlink into an
# existing, writable PATH directory when it finds one. That symlink is a
# convenience, not the install: the real tree always lands in ~/.grok/bin, and
# when no such directory is on PATH the installer's only other move is to
# append a PATH line to .bashrc, which nothing in a sandbox sources. The overlay
# ships neither — its own /usr/local/bin shim is staged below.
#
# HOW THE PIN REACHES THE INSTALLER: as install.sh's first positional argument,
# which `bash -s` is what forwards to a script read from a pipe. That is the
# installer's own documented interface for it (`... | bash -s 0.1.42`), and it
# validates the target itself, refusing anything that is not X.Y.Z[-suffix].
# With it set the installer skips its channel-pointer fetch and builds the
# artifact URL from this version, so a value naming no published release fails
# the download rather than falling back to the newest.
#
# The comparison afterwards is what makes the provide trustworthy rather than
# merely requested: the descriptor publishes `grok@${GROK_VERSION}`, so an
# install that resolved to something else would ship an overlay whose provide
# lies about its own content — the one failure mode worse than floating.
# `grok --version` prints `grok <version> (<commit>)`, so the second field is the
# number to match. It runs through ~/.grok/bin/grok, the path the overlay
# actually carries, rather than through the PATH symlink it leaves behind.
#
# Running the binary is not a new class of build-time behavior: install.sh
# already executes the freshly downloaded artifact itself, once as
# `<binary> --version` to verify it starts at all and again to generate shell
# completions, and fails the install if the first of those does not run.
RUN set -eux; \
    [ -n "$GROK_VERSION" ] || { echo "GROK_VERSION must be set" >&2; exit 1; }; \
    mkdir -p "$HOME/.local/bin"; \
    curl -fsSL https://x.ai/cli/install.sh | bash -s "$GROK_VERSION"; \
    reported="$("$HOME/.grok/bin/grok" --version)"; \
    echo "grok --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $2}')"; \
    [ "$installed" = "$GROK_VERSION" ] || { \
      echo "pin mismatch: descriptor says $GROK_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

USER root
# The overlay carries ~/.grok/bin, where the installer puts the binaries, and
# points its own shim straight at it. Copying ~/.local alone was the bug this
# replaces: on a base whose PATH does not already carry ~/.local/bin the
# installer writes no symlink there at all, and even when it does, the link
# resolves into ~/.grok — so the overlay shipped either an empty tree or a
# dangling link, and `grok` could not run on any base it composed onto.
#
# Both ~/.grok/bin and ~/.grok/downloads travel, and neither is optional:
# `bin/grok` and `bin/agent` are relative symlinks into `../downloads`, which
# is where the platform binary actually sits. downloads/ looks like installer
# scratch and is not.
#
# What is left behind is the per-session state the installer also writes there
# (config.toml, active_sessions.json): grok recreates it, and shipping it as
# image content would override whatever the composed sandbox already had.
#
# `test -x` follows the symlink to the real binary, so a change of install
# layout upstream fails the build here. Checking the symlink alone is what let
# the previous version pass while shipping nothing that could run.
RUN set -eux; \
    test -x /home/agent/.grok/bin/grok; \
    mkdir -p /out/home/agent/.grok /out/usr/local/bin; \
    cp -a /home/agent/.grok/bin /out/home/agent/.grok/bin; \
    cp -a /home/agent/.grok/downloads /out/home/agent/.grok/downloads; \
    chown -R 1000:1000 /out/home/agent; \
    ln -s /home/agent/.grok/bin/grok /out/usr/local/bin/grok

# The bin shim above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them. v2 declared no environment.variables, so there is no env
# file to write beside it.

# The overlay: the CLI's install tree and its bin shim, landing on any base.
# No ENTRYPOINT — the base workload's launch command stays, and the user runs
# `grok` from the shell. v2's `--yolo --no-auto-update` were entrypoint flags
# and belong to the workload; a user running `grok` here passes their own.
FROM scratch
COPY --from=build /out /
