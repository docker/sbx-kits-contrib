# syntax=docker/dockerfile:1.7
# Base image for the `hermes-agent` sandbox kit.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant: Hermes' terminal backend defaults to "local"
# (hermes_cli/setup_terminal.py) -- commands run in this container, and
# Docker is just one of seven equally unprovisioned backends.

# Empty resolves upstream's newest stable release at build time; a release tag
# pins it. Pinning does not pin the layer: the cache key below is independent of
# this arg, so a pinned build still re-runs the install layer whenever upstream
# publishes.
ARG HERMES_VERSION=""

# Cache key only -- the RUN below never reads this file. BuildKit re-fetches the
# URL on every build to compute the layer's digest, and the feed changes on
# every published release, which is what invalidates the install layer below. A
# pre-release changes it too, costing one rebuild that still resolves the newest
# stable tag. The feed is roughly 340 KB and ships in the image. It is
# root-owned under /tmp's sticky bit (this ADD precedes the USER switch below),
# so an `rm` of it as agent would fail the RUN, and a later-layer delete would
# only add a whiteout on top of this layer.
ADD --chmod=644 https://github.com/NousResearch/hermes-agent/releases.atom /tmp/hermes-releases.atom

USER agent
WORKDIR /home/agent/workspace

# The tag comes from github.com's own /releases/latest redirect, not from the
# releases API: unauthenticated api.github.com quota is counted per source IP
# and hosted CI runners share egress addresses, so the API intermittently
# rate-limits the fetch mid-build, and BuildKit's URL fetch carries no token to
# lift that limit. The redirect resolves the newest release, skipping drafts and
# pre-releases.
#
# scripts/install.sh, not `pip install hermes-agent`: PyPI trails the git
# tags by weeks, too stale for a nightly-rebuilt image. Fetched from the
# resolved tag (not main) so the installer and the code it installs match.
#
# --skip-browser/--skip-computer-use drop Playwright and the macOS-only
# cua-driver fetch -- neither is part of this kit's supported surface.
#
# install.sh always installs its `all` extra; `anthropic` is added
# afterward because this kit wires Anthropic up as a first-class provider,
# so it can't be left to upstream's lazy-install-at-runtime path.
#
# `hermes --version` is the build-time gate: a broken release fails the
# build instead of shipping a non-starting agent.
RUN set -eu; \
    tag="${HERMES_VERSION}"; \
    if [ -z "$tag" ]; then \
        tag="$(curl -fsSI -o /dev/null -w '%{redirect_url}' https://github.com/NousResearch/hermes-agent/releases/latest | sed -n 's#.*/releases/tag/##p')"; \
    fi; \
    if [ -z "$tag" ]; then \
        echo "Failed to resolve a hermes-agent release tag: HERMES_VERSION is empty and the request to github.com/NousResearch/hermes-agent/releases/latest failed or did not redirect to a release tag (curl's own error, if any, is printed above). Pass --build-arg HERMES_VERSION=<tag>." >&2; \
        exit 1; \
    fi; \
    curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${tag}/scripts/install.sh" -o /tmp/hermes-install.sh; \
    chmod +x /tmp/hermes-install.sh; \
    /tmp/hermes-install.sh --branch "$tag" --skip-setup --skip-browser --skip-computer-use --non-interactive; \
    rm -f /tmp/hermes-install.sh; \
    "$HOME/.hermes/bin/uv" pip install --python "$HOME/.hermes/hermes-agent/venv/bin/python" \
        -e "$HOME/.hermes/hermes-agent[anthropic]"; \
    "$HOME/.local/bin/hermes" --version

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

# COPY (not a files/ reference) so the image's own CMD works standalone,
# independent of the kit's files/home/ copy that sandbox.entrypoint uses.
COPY --chmod=0755 files/home/.local/bin/hermes-start.sh /usr/local/bin/hermes-start

# Overrides the base's inherited flavor -- left alone it would report
# "shell" rather than "hermes-agent".
LABEL com.docker.sandboxes.flavor="hermes-agent"

# Nothing in sbx reads this; records what the floating base actually
# resolved to at build time.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent/workspace
CMD ["/usr/local/bin/hermes-start"]
