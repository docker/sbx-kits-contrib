# syntax=docker/dockerfile:1.7
# Base image for the `hermes-agent` sandbox kit.
#
# Hermes is pre-baked so sandbox creation is fast and so its install-time
# fetches (uv, a standalone Python, a git clone, an editable pip install)
# never have to sit in this kit's *runtime* network allowlist -- the engine
# enforces one allowlist per sandbox and cannot distinguish a build-time
# fetch from one the running agent might make.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# pi/openclaw/kiro/copilot.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# No `-docker` variant and no start-docker label: Hermes' terminal backend
# defaults to "local" (hermes_cli/setup_terminal.py, cfg_get(..., default=
# "local")) -- commands run in this container. Docker is one of seven
# selectable backends (alongside ssh/singularity/modal/daytona/vercel), all
# equally unprovisioned here; picking that one to support and not the other
# six would be arbitrary, so this image carries no Docker engine.

# Upstream's tagged releases (checked via the GitHub releases API) land
# roughly weekly, while main takes dozens of commits a day between them --
# unlike a curated npm dist-tag, main HEAD here is not something a maintainer
# chose to call a release; re-check the release cadence before trusting this
# reasoning to still hold. HERMES_REF selects the GitHub releases API path
# segment: "latest" (default) resolves upstream's newest tagged release, or
# "tags/vX.Y.Z" to pin one.
#
# The ADD below is what makes rolling updates work under CI's layer cache:
# BuildKit re-fetches the URL on every build to compute its digest, so this
# layer is a cache hit when the resolved release has not changed and re-runs
# -- picking up the new tag -- exactly when it has.
ARG HERMES_REF=latest
ADD --chmod=644 https://api.github.com/repos/NousResearch/hermes-agent/releases/${HERMES_REF} /tmp/hermes-release.json

# /tmp/hermes-release.json is root-owned (this ADD runs before the USER switch
# below) inside /tmp's sticky bit, so the agent user below can read it but
# cannot unlink it -- an `rm` on it as agent fails the build. It is also never
# removed: the file lives in the ADD's own layer, so deleting it in a later
# layer would only add a whiteout on top of the ~1 KB that ships either way.
USER agent
WORKDIR /home/agent

# Installs via upstream's own scripts/install.sh rather than a raw `pip
# install hermes-agent` from PyPI: PyPI trails the git tags by six-plus weeks
# (0.19.0 published 2026-07-20, against v2026.8.31/0.21.0 on GitHub the same
# day this was written), so it is not a fresh-enough source for an image a
# nightly job is meant to keep current. install.sh is fetched from the
# resolved tag itself rather than from main, so the installer logic and the
# code it installs come from the same commit -- reproducible given that tag,
# modulo install.sh's own floating dependencies (uv, npm registry
# resolution).
#
# --skip-browser / --skip-computer-use drop upstream's Playwright/Chromium
# download and its macOS-only cua-driver fetch. Neither is part of this
# kit's supported surface (spec.yaml/README cover Anthropic, OpenAI,
# OpenRouter only); skipping them keeps the build inside a tight image-size
# budget and drops two more floating install-time dependencies this kit
# would otherwise have to carry.
#
# install.sh always installs its own `all` extra (upstream's own curated
# eagerly-installed set -- everything else is deliberately lazy-installed
# from PyPI at first use, a policy upstream adopted after a quarantined
# transitive package once hit installs pulling from an unpinned range) and
# takes no flag to add another. `anthropic` -- the native Anthropic SDK --
# is added afterward, into the same venv install.sh already created, because
# this kit's own credentials block wires Anthropic up as a first-class
# provider (api.anthropic.com, both API-key and OAuth shapes). Leaving it out
# of the bake would mean the first real Anthropic call triggers upstream's
# lazy-install path against PyPI at *runtime* -- exactly the class of
# dependency this conversion exists to remove.
#
# `hermes --version` is the build-time gate: it actually runs the installed
# code, so a release this installer cannot complete, or that imports
# something broken, fails the build -- and so the nightly publish -- instead
# of shipping a non-starting agent.
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

# Everything outside the `all` + `anthropic` extras baked above --
# alternate model providers, the messaging-platform gateways, TTS/STT, other
# search backends, memory providers -- is a tools/lazy_deps.py entry that
# Hermes would otherwise pip-install from PyPI the first time a feature is
# used. HERMES_DISABLE_LAZY_INSTALLS is upstream's own official mechanism for
# exactly this: NousResearch's published Docker image sets it for the same
# reason (an immutable install tree), and upstream's own docs describe it as
# the "internal bridge var set automatically in the official Docker image to
# prevent runtime dependency installs". Unlike that image, this one sets no
# HERMES_LAZY_INSTALL_TARGET to redirect installs to -- there is no writable
# volume in this sandbox to redirect them into -- so every lazy-install
# attempt is refused outright rather than relocated.
#
# This is what makes a trimmed runtime network allowlist correct rather than
# merely convenient: a feature outside the baked set now fails fast with
# `FeatureUnavailable`, naming the exact `pip install` command an operator
# would run by hand, instead of that same pip install silently hanging or
# erroring against a blocked host.
ENV HERMES_DISABLE_LAZY_INSTALLS=1

# COPY, not a reference to the kit's files/ tree: this is what makes the
# image's own CMD work when the image is run directly (docker run, or before
# the kit's setup.startup hook has ever executed), independent of sbx. The
# kit's sandbox.entrypoint in spec.yaml points at the files/home/ copy of
# this same script instead, so a fix to it reaches an existing sandbox on
# its next create without waiting on an image republish.
COPY --chmod=0755 files/home/.local/bin/hermes-start.sh /usr/local/bin/hermes-start

# Both labels below OVERRIDE values inherited from the base image, which
# describe the base rather than this image. Overriding `flavor` is not
# optional: sbx reads it as the image's agent identifier, and left inherited
# it would report "shell" rather than "hermes-agent".
LABEL com.docker.sandboxes.flavor="hermes-agent"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the
# produced image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["/usr/local/bin/hermes-start"]
