# syntax=docker/dockerfile:1.7
# Content recipe for the `hermes-agent` kit — the v2 Dockerfile, renamed to
# the stem hermes-agent.dockerfile so the descriptor beside it finds it
# without a `dockerfile:` field.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant: Hermes' terminal backend defaults to "local"
# (hermes_cli/setup_terminal.py) -- commands run in this container, and
# Docker is just one of seven equally unprovisioned backends.

# THE PIN. The kit's `version` arg arrives as this build arg: hermes-agent.yaml
# validates its shape and expands the same value into `provides` and into its own
# `version:` field. It is the release tag without its leading `v`, which the RUN
# below puts back -- SPEC-v3 §5.2 admits no `v` prefix in the version the
# descriptor publishes.
#
# No default here any more, and that is the change. It used to default to the
# empty string, which the RUN read as "resolve upstream's newest stable"; that
# resolution is gone with it, because a build that picks its own version cannot be
# the build a pinned provide describes. An empty value now fails the build.
ARG HERMES_VERSION

# REMOVED WITH THE PIN: an `ADD` of
# https://github.com/NousResearch/hermes-agent/releases.atom to
# /tmp/hermes-releases.atom. Nothing read the file -- it was a cache key, there so
# that BuildKit's re-fetch of the feed would invalidate the install layer whenever
# upstream published, keeping a floating install fresh. A pinned install wants the
# opposite: the layer's cache key is now the pin itself (the RUN below expands
# HERMES_VERSION), so a re-run on someone else's release would reinstall the same
# tag for nothing, and bumping the arg invalidates the layer on its own. It also
# took a root-owned 340 KB copy of the feed into the published image, which no
# sandbox had a use for.

USER agent
WORKDIR /home/agent

# HOW THE PIN REACHES THE INSTALLER: as the git tag. `v` + the arg is the tag
# name, which is fetched from raw.githubusercontent.com to get that release's own
# copy of the installer and then handed to it as `--branch`, so install.sh clones
# and checks out exactly that release. A value naming no tag fails the fetch of
# the install script rather than falling through to a default.
#
# What used to stand here instead: when HERMES_VERSION was empty the build
# resolved the newest release itself, from github.com's own /releases/latest
# redirect (deliberately not the releases API, whose unauthenticated quota is
# counted per source IP and intermittently rate-limits hosted CI mid-build). That
# resolution is gone -- it is now how a human bumps the arg's default, recorded in
# hermes-agent.yaml, rather than something the build does behind the pin.
#
# scripts/install.sh, not `pip install hermes-agent`: PyPI trails the git
# tags by weeks, too stale for a nightly-rebuilt image. Fetched from the
# pinned tag (not main) so the installer and the code it installs match.
#
# --skip-browser/--skip-computer-use drop Playwright and the macOS-only
# cua-driver fetch -- neither is part of this kit's supported surface.
#
# install.sh always installs its `all` extra; `anthropic` is added
# afterward because this kit wires Anthropic up as a first-class provider,
# so it can't be left to upstream's lazy-install-at-runtime path.
#
# `hermes --version` is the build-time gate: a broken release fails the
# build instead of shipping a non-starting agent. It is also the pin's check now,
# and the field it compares needs saying, because Hermes reports two numbers.
# Its first line is
#
#     Hermes Agent v<package version> (<release date>)
#
# optionally followed by `· upstream <sha>` for a git install, which this is. The
# package version (0.21.3 at the tag pinned here) is `hermes_cli.__version__` and
# no installer input selects it; the parenthesised release date is
# `__release_date__`, which upstream stamps with the release's own tag minus the
# `v` -- the identity this kit asked for. So the pin is matched against
# `(<version>)`, parentheses included, which keeps it anchored to that field
# rather than matching the digits anywhere in the line.
#
# The descriptor publishes `hermes-agent@${HERMES_VERSION}`, so a checkout whose
# own stamp disagrees with the tag it came from fails the build instead of
# publishing a provide that lies about its content -- the one failure mode worse
# than floating. If a future release ever stamps something other than its tag,
# this is where that shows up, and the honest fix is to look rather than to
# loosen the comparison.
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

# Everything outside the `all` + `anthropic` extras baked above -- other
# providers, gateways, TTS/STT, search backends, memory providers -- is a
# tools/lazy_deps.py entry Hermes would otherwise pip-install from PyPI at
# first use. HERMES_DISABLE_LAZY_INSTALLS is upstream's own switch for
# this; unlike upstream's own Docker image, this one sets no
# HERMES_LAZY_INSTALL_TARGET, so a lazy-install attempt is refused outright
# rather than relocated.
#
# This only closes the pip-install surface, not every runtime HTTP fetch
# Hermes makes on its own (the model catalogue, its startup update check) --
# those still need their own hosts allowed at runtime regardless. A feature
# outside the baked set fails fast with `FeatureUnavailable` instead of a
# pip install hanging or erroring against a blocked host.
ENV HERMES_DISABLE_LAZY_INSTALLS=1

# v2's environment.variables, in the slot OCI already owns for static env --
# the v3 descriptor carries none. The startup hook declares HERMES_HOME in its
# own `env:` list, because hook environments are deny-by-default and an image
# ENV is not part of the platform baseline.
ENV HERMES_HOME=/home/agent/.hermes

# MIGRATION NOTE: v2 staged the files/home/ tree into the container through a
# kit-loader convention v3 has no counterpart for — the descriptor's only file
# mechanism is lifecycle files[].content, which is inline text rather than a
# path reference. So the recipe stages them, at the same absolute paths the
# entrypoint and the startup hook already named.
#
# --chmod=0755 rather than the loader's 0644: the kit owns the mode here. Both
# are still invoked through `sh` (the entrypoint below, and the hook in
# hermes-agent.yaml) because that is what v2 did and it works either way.
COPY --chown=agent:agent --chmod=0755 files/home/.local/bin/hermes-start.sh /home/agent/.local/bin/hermes-start.sh
COPY --chown=agent:agent --chmod=0755 files/home/.local/bin/hermes-anthropic-auth.sh /home/agent/.local/bin/hermes-anthropic-auth.sh

# A PATH convenience, kept from v2. Its original rationale -- "so the image's
# own CMD works standalone, independent of the kit's files/home/ copy" -- no
# longer applies: there is one image now, and ENTRYPOINT below carries the
# kit's launch command rather than a CMD.
COPY --chmod=0755 files/home/.local/bin/hermes-start.sh /usr/local/bin/hermes-start

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "hermes-agent".
LABEL com.docker.sandboxes.flavor="hermes-agent"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent

# v2's `sandbox.entrypoint`, verbatim. Kit content, not a script written at
# install time: the entrypoint has to source the Anthropic auth env file the
# startup hook writes, then exec the binary baked into the image. It replaces
# the v2 file's `CMD ["/usr/local/bin/hermes-start"]` rather than joining it:
# the launch argv is Entrypoint + Cmd, so keeping both would pass the CMD path
# to hermes as an argument.
ENTRYPOINT ["sh", "/home/agent/.local/bin/hermes-start.sh"]
