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

# HERMES_REF selects the GitHub releases API path segment: "latest"
# resolves the newest tagged release, or "tags/vX.Y.Z" to pin one. BuildKit
# re-fetches the URL on every build to compute its digest, so this layer
# re-runs exactly when the resolved release changes.
ARG HERMES_REF=latest
ADD --chmod=644 https://api.github.com/repos/NousResearch/hermes-agent/releases/${HERMES_REF} /tmp/hermes-release.json

# /tmp/hermes-release.json is root-owned (this ADD runs before the USER switch
# below) inside /tmp's sticky bit, so the agent user below can read it but
# cannot unlink it -- an `rm` on it as agent fails the build. It is also never
# removed: the file lives in the ADD's own layer, so deleting it in a later
# layer would only add a whiteout on top of the ~1 KB that ships either way.
USER agent
WORKDIR /home/agent

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
    tag="$(grep -oP '"tag_name":\s*"\K[^"]+' /tmp/hermes-release.json)"; \
    [ -n "$tag" ]; \
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
WORKDIR /home/agent
CMD ["/usr/local/bin/hermes-start"]
