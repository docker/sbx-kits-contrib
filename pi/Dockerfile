# syntax=docker/dockerfile:1.7
# Base image for the `pi` sandbox kit.
#
# pi is pre-baked so sandbox creation is fast: the kit used to npm-install it
# at create time, which put a multi-minute download in front of every new
# sandbox.
#
# Built and published by build-and-publish-kits.yml, the shared kit-image
# pipeline (see ../PUBLISHING.md) -- no bespoke workflow needed, same as
# openclaw/kiro/copilot.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# Rolling updates by design: pi tracks the `latest` dist-tag, and the nightly
# scheduled run of build-and-publish-kits.yml rebuilds this image against it.
# The ADD below is what makes that work under CI's layer cache: BuildKit
# re-downloads the URL on every build to compute its digest, so the install
# layer re-runs exactly when the fetched packument changes and is a cache hit
# otherwise. Without it, the unchanging RUN line would hit the gha cache
# forever and the nightly rebuild would ship a stale binary.
#
# PI_VERSION is part of the URL, so overriding it reproduces a specific
# version *and* keeps the cache key stable: a pinned build fetches that
# version's document, which does not change when upstream publishes something
# unrelated.
ARG PI_VERSION=latest

# --chmod=644 because a URL ADD lands 0600 root-owned by default, and the RUN
# below reads this file as agent.
USER root
ADD --chmod=644 https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/${PI_VERSION} /tmp/pi-latest.json
# No Node install step: the template already ships Node 22.22.1, which
# satisfies pi's `engines.node >= 22.19.0`. (openclaw's image has to run
# `n 22` because openclaw needs a newer minor than the template had at the
# time -- pi does not.)
#
# The version installed is read out of the document ADDed above rather than
# re-resolved from the registry at RUN time, so what lands in the image is a
# pure function of that layer's content. Within a single build that pins both
# architectures together: amd64 and arm64 resolve the same packument layer, so
# one manifest list cannot mix two releases. Across separate builds it does
# not -- each buildx invocation re-fetches the URL, so a release published in
# between changes the digest and the later build installs something the
# earlier one never saw. What covers that is the `pi --version` gate below: it
# re-runs inside whichever build cache-misses, so a broken release fails that
# build rather than being published.
#
# The install runs as agent because the global prefix is agent-owned in the
# template, so installing as agent gets the ownership `pi update --self` and
# `pi install` need (they run as agent inside the sandbox and would otherwise
# fail on EACCES). Installing as root and chowning afterwards would be worse
# on both counts: root-owned files land in the tree first, and a recursive
# chown -- even to the owner the files already have -- copies the template's
# entire npm tree up into this image's layer, adding megabytes to every
# nightly rebuild. The kit's old create-time install ran as uid 1000 for the
# same ownership reason.
#
# `pi --version` is a build-time gate, not a smoke test for its own sake: npm
# only WARNS on an engines mismatch (EBADENGINE, exit 0), and CI's image
# verification only checks that the binary is on PATH. Executing pi is what
# actually fails the build -- and so blocks the nightly publish -- when
# upstream ships a release this image's Node cannot run, or one whose bin
# exists but whose entry module throws.
#
# /tmp/pi-latest.json is deliberately not removed: it lives in the ADD's own
# layer, so deleting it here would only add a whiteout on top of the ~5 KB
# that ships either way.
USER agent
RUN version="$(node -p 'require("/tmp/pi-latest.json").version')" && \
    npm install -g "@earendil-works/pi-coding-agent@${version}" && \
    pi --version

# The global bin dir is on PATH in this image, but not in every context that
# may invoke the binary (startup commands and some exec paths run with a
# minimal PATH). A symlink somewhere always on PATH costs nothing. /usr/local/bin
# is root-owned, so this one step goes back to root.
USER root
RUN ln -sf "$(npm prefix -g)/bin/pi" /usr/local/bin/pi

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
# this image's agent as "shell-docker". So it must be the kit's own name: `pi`.
LABEL com.docker.sandboxes.flavor="pi"

# Informational only -- nothing in sbx reads this. Worth setting because the
# base is a floating tag rebuilt nightly, so this is the one place the produced
# image records what it was actually built on.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["pi"]
