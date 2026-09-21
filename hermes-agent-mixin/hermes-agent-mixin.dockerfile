# syntax=docker/dockerfile:1.7
# Overlay recipe for the hermes-agent mixin.
#
# Hermes installs itself as a Python virtualenv: scripts/install.sh clones the
# project and `uv pip install -e` wires it up, which bakes absolute
# interpreter paths into every console-script shebang and into the editable
# install's own path records. There is no --prefix that relocates that
# afterwards, so this takes the shape the guide prescribes for an
# unrelocatable install — the workload's own base as a build stage, the
# unmodified install run on it, and the specific resulting paths copied into a
# scratch overlay.
#
# The install runs as `agent` with HOME at /home/agent, the sandbox runtime's
# own home, so those baked paths are already correct when the overlay lands.
# Staging it under a build-only HOME and moving the tree afterwards would
# leave every shebang pointing at a directory the composed sandbox does not
# have.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE} AS build

# THE PIN. The kit's `version` arg arrives as this build arg:
# hermes-agent-mixin.yaml validates its shape and expands the same value into
# `provides` and into its own `version:` field. It is the release tag without its
# leading `v`, which the RUN below puts back -- SPEC-v3 §5.2 admits no `v` prefix
# in the version the descriptor publishes.
#
# No default here any more, and that is the change. It used to default to the
# empty string, which the RUN read as "resolve upstream's newest stable"; that
# resolution is gone with it, because a build that picks its own version cannot be
# the build a pinned provide describes. An empty value now fails the build.
ARG HERMES_VERSION

# REMOVED WITH THE PIN: an `ADD` of the repository's releases.atom feed to
# /tmp/hermes-releases.atom. Nothing read it -- it was a cache key, there so that
# BuildKit's re-fetch would invalidate the install layer whenever upstream
# published, keeping a floating install fresh. A pinned install wants the
# opposite: the cache key is now the pin itself (the RUN below expands
# HERMES_VERSION), so a re-run on someone else's release would reinstall the same
# tag for nothing, and bumping the arg invalidates the layer on its own.

USER root
# Ownership is scoped to /out/home/agent, not /out/home: an overlay's directory
# entries override the base's, so a staged /out/home owned by the agent would
# hand /home itself away on every base this composes onto. /home stays root's.
RUN mkdir -p /out/home/agent /out/etc/profile.d && chown -R agent:agent /out/home/agent

USER agent
WORKDIR /home/agent

# The install, unmodified from the workload recipe: `v` + the pin is the git tag,
# fetched from raw.githubusercontent.com for that release's own copy of the
# installer and handed to it as `--branch`, so install.sh checks out exactly that
# release; install.sh rather than PyPI (which trails the git tags by weeks);
# --skip-browser/--skip-computer-use because neither is part of this kit's
# supported surface; and the `anthropic` extra added afterward because this kit
# wires Anthropic up as a first-class provider.
#
# `hermes --version` is the build-time gate and the pin's check. Its first line is
# `Hermes Agent v<package version> (<release date>)`, optionally followed by
# `· upstream <sha>` for a git install, which this is. The package version
# (0.21.3 at the tag pinned here) is selected by nothing; the parenthesised
# release date is upstream's `__release_date__`, which for a release tag is the tag
# minus its `v` -- the identity this kit asked for. So the pin is matched against
# `(<version>)`, parentheses included, to keep it anchored to that field. The
# descriptor publishes `hermes-agent@${HERMES_VERSION}`, so a checkout whose stamp
# disagrees with its tag fails the build rather than shipping an overlay whose
# provide lies about its content.
RUN set -eu; \
    [ -n "${HERMES_VERSION}" ] || { echo "HERMES_VERSION must be set" >&2; exit 1; }; \
    tag="v${HERMES_VERSION}"; \
    curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${tag}/scripts/install.sh" -o /tmp/hermes-install.sh; \
    chmod +x /tmp/hermes-install.sh; \
    /tmp/hermes-install.sh --branch "$tag" --skip-setup --skip-browser --skip-computer-use --non-interactive; \
    rm -f /tmp/hermes-install.sh; \
    "$HOME/.hermes/bin/uv" pip install --python "$HOME/.hermes/hermes-agent/venv/bin/python" \
        -e "$HOME/.hermes/hermes-agent[anthropic]"; \
    reported="$("$HOME/.local/bin/hermes" --version | head -1)"; \
    echo "hermes --version: $reported"; \
    case "$reported" in \
      *"(${HERMES_VERSION})"*) ;; \
      *) echo "pin mismatch: descriptor says ${HERMES_VERSION}, hermes reports '$reported'" >&2; exit 1 ;; \
    esac

# The startup hook's script, at the absolute path the descriptor names.
#
# MIGRATION NOTE: this file is a copy of
# ../hermes-agent/files/home/.local/bin/hermes-anthropic-auth.sh, not a
# reference to it. A kit's build context is rooted at its own descriptor's
# directory and may not escape it (SPEC-v3 §4), so a sibling kit's assets are
# unreachable from here. The two must move together — see this kit's README.
#
# hermes-start.sh is deliberately NOT carried: it exists to source the auth
# env file before exec'ing the binary, and that is an entrypoint's job. A
# mixin has no entrypoint, and the auth script already appends a source line
# to ~/.profile, which is what a login shell picks up.
COPY --chown=agent:agent --chmod=0755 files/home/.local/bin/hermes-anthropic-auth.sh /home/agent/.local/bin/hermes-anthropic-auth.sh

USER root
# v2's environment.variables plus the recipe's own HERMES_DISABLE_LAZY_INSTALLS.
# A mixin's image config is not the composed image's, so ENV would be dropped
# at assembly — the exports ride the overlay instead, sourced by the base
# workload's login shell.
#
# HERMES_DISABLE_LAZY_INSTALLS is load-bearing rather than cosmetic: it is
# upstream's own switch for refusing runtime pip installs, and it is why the
# descriptor's allow list carries no pypi.org. Without it here, a lazy install
# would hang against a blocked host instead of failing fast with
# `FeatureUnavailable`.
RUN cat > /out/etc/profile.d/hermes-agent-env.sh <<'EOF'
export HERMES_HOME=/home/agent/.hermes
export HERMES_DISABLE_LAZY_INSTALLS=1
EOF

# The specific resulting paths: the venv and project tree under ~/.hermes, and
# the launcher plus the startup hook's script under ~/.local/bin.
RUN set -eux; \
    cp -a /home/agent/.hermes /out/home/agent/.hermes; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    chown -R 1000:1000 /out/home/agent; \
    test -x /out/home/agent/.local/bin/hermes; \
    test -x /out/home/agent/.local/bin/hermes-anthropic-auth.sh; \
    mkdir -p /out/usr/local/bin; \
    ln -s /home/agent/.local/bin/hermes /out/usr/local/bin/hermes

# The bin shim above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them.

# The overlay: the Hermes install and its auth script, landing on any base.
# No ENTRYPOINT — the base workload's launch command stays, and the user runs
# `hermes` from a login shell.
FROM scratch
COPY --from=build /out /
