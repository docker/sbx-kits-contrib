# syntax=docker/dockerfile:1.7
# The pi workload's content. This is the v2 kit's Dockerfile: v2 published it
# as docker.io/sbx/pi-image:latest and pointed `sandbox.image` at the result,
# while a v3 workload's layers *are* the root filesystem -- so the
# intermediate publish disappears and this recipe builds the kit directly.
# v2's sandbox.entrypoint lands at the bottom, in the image config that
# already owns runtime config.
#
# pi is pre-baked so sandbox creation is fast: the kit used to npm-install it
# at create time, which put a multi-minute download in front of every new
# sandbox.
#
# The base is a floating tag, which is why CI also rebuilds on a schedule.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a global
# build arg, visible only to FROM lines. Without this, the LABEL below would
# expand to an empty string.
ARG BASE_IMAGE

# pi's `find` tool is fd underneath. On first use pi probes the system for `fd`
# or `fdfind` and, finding neither, downloads a release binary from GitHub
# (sharkdp/fd) into its own bin dir. This repo's e2e runs every kit under
# `sbx policy init deny-all` and the kit's allowlist names no GitHub release
# host, so that download cannot succeed and `find` is simply broken; even where
# egress is permissive, every fresh sandbox pays the probe and then the download
# the first time the agent looks for a file. Baking the package settles it for
# every sandbox at build time.
#
# Ubuntu's package is `fd-find` and it installs the binary as `fdfind`. pi's
# probe accepts that name as-is; the symlink is for humans at the shell, who
# expect `fd`.
#
# ripgrep needs no equivalent layer -- pi probes the system for `rg` exactly the
# same way, and the template already ships /usr/bin/rg. Nothing to add here.
#
# Deliberately placed above the ARG PI_VERSION / ADD section below: every layer
# after that ADD re-runs whenever upstream publishes a release, and this one has
# nothing to do with which pi version is installed. Kept up here it stays a
# cache hit across the nightly rebuilds.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends fd-find && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd

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
# unrelated. It is not a kit arg: the descriptor's provide is unversioned
# precisely because the default floats, and a kit arg would have to pin.
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
# nightly rebuild.
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
# does not own. This stays a label: it is a request to the runtime, not a v3
# capability, and there is no descriptor field that means it.
#
# Setting it over a base with no Docker engine yields a sandbox started in
# Docker mode with nothing to run. Since BASE_IMAGE is overridable, CI asserts
# the engine is really present rather than trusting this label.
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
# v2's sandbox.entrypoint. Setting ENTRYPOINT also clears the CMD inherited
# from the base (and replaces the v2 image's own `CMD ["pi"]`), so nothing is
# appended to it -- which is what makes the agent-sessions prompt tail land as
# `pi -p <prompt>`.
ENTRYPOINT ["pi"]
