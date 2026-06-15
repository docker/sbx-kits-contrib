#!/usr/bin/env bash
# Build the NanoClaw sandbox image.
#
# The inner container images (nanoclaw-agent, OneCLI gateway, postgres) are
# NOT embedded in the sandbox image — they are pulled by digest from their
# registries on first boot (scripts/seed-images.sh). This script:
#
#   TARGET=agent  clone nanoclaw @ pinned ref, build the nanoclaw-agent
#                 image from its container/ dir, and push it if AGENT_IMAGE
#                 names a registry repo (so first boot has something to pull)
#   TARGET=sbx    docker build the sandbox image, baking the digest-pinned
#                 inner-image pin list (AGENT_IMAGE/ONECLI_IMAGE/POSTGRES_IMAGE)
#   TARGET=all    both, for local dev (agent built as a local tag; see the
#                 local-testing note below)   [default]
#
# Overridable via env:
#   NANOCLAW_REPO    upstream repo URL
#   NANOCLAW_REF     git ref to bake (pin a commit for reproducible builds)
#   ONECLI_VERSION   OneCLI gateway version — keep in lockstep with
#                    ONECLI_GATEWAY_VERSION in nanoclaw's setup/onecli.ts
#   IMAGE            output tag for the sandbox image
#   AGENT_IMAGE      ref baked into the pin list AND the build/push target for
#                    the agent image. A registry ref (docker.io/ns/nanoclaw-
#                    agent@sha256:... or :tag) is pushed and pulled at boot;
#                    the default local tag is not pushed.
#   ONECLI_IMAGE     ref baked into the pin list for the OneCLI gateway
#   POSTGRES_IMAGE   ref baked into the pin list for postgres
#
# Local testing note: with TARGET=all the agent is built as a local-only tag
# (nanoclaw-agent:latest), which seed-images.sh cannot pull. To exercise a
# local sandbox end-to-end, push the agent to a registry (set AGENT_IMAGE to
# a repo ref) or `sbx exec <sandbox> -- docker load` it manually.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOCLAW_REPO="${NANOCLAW_REPO:-https://github.com/nanocoai/nanoclaw.git}"
NANOCLAW_REF="${NANOCLAW_REF:-36cbf17e107fd0f8daea4ceb2ac523d9f0d88915}"
ONECLI_VERSION="${ONECLI_VERSION:-1.23.0}"
IMAGE="${IMAGE:-nanoclaw-sbx:local}"
TARGET="${TARGET:-all}"
AGENT_IMAGE="${AGENT_IMAGE:-nanoclaw-agent:latest}"
ONECLI_IMAGE="${ONECLI_IMAGE:-ghcr.io/onecli/onecli:${ONECLI_VERSION}}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:18-alpine}"
# Local tags the inner images are retagged to after pull, i.e. the names
# NanoClaw/OneCLI reference. Pull refs above may be digest-pinned; these stay
# the conventional tags.
AGENT_TAG="${AGENT_TAG:-nanoclaw-agent:latest}"
ONECLI_TAG="${ONECLI_TAG:-ghcr.io/onecli/onecli:${ONECLI_VERSION}}"
POSTGRES_TAG="${POSTGRES_TAG:-postgres:18-alpine}"

build_agent() {
    local workdir
    workdir="$(mktemp -d /tmp/nanoclaw-agent.XXXXXX)"
    trap 'rm -rf "$workdir"' RETURN

    echo "==> Cloning nanoclaw @ ${NANOCLAW_REF}"
    git clone "$NANOCLAW_REPO" "$workdir/nanoclaw"
    git -C "$workdir/nanoclaw" checkout --quiet "$NANOCLAW_REF"

    # Switch the agent image's apt sources to HTTPS before building. Some
    # networks (notably corporate ones with TLS-inspecting appliances) block
    # apt's plain-HTTP traffic; HTTPS works everywhere deb.debian.org does.
    # node:22-slim ships no CA bundle (ca-certificates is only installed by
    # the apt step itself), so borrow alpine's bundle for the bootstrap —
    # the real ca-certificates package overwrites it moments later.
    local agent_dockerfile="$workdir/nanoclaw/container/Dockerfile"
    local ca_copy='COPY --from=alpine:3 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt'
    local apt_https='RUN sed -i "s|http://deb.debian.org|https://deb.debian.org|g" /etc/apt/sources.list.d/debian.sources'
    awk -v l1="$ca_copy" -v l2="$apt_https" '{print} /^FROM /{print l1; print l2}' \
        "$agent_dockerfile" > "$agent_dockerfile.tmp"
    mv "$agent_dockerfile.tmp" "$agent_dockerfile"
    grep -q 'https://deb.debian.org' "$agent_dockerfile" || {
        echo "error: failed to patch apt sources in $agent_dockerfile" >&2
        exit 1
    }

    echo "==> Building agent image ${AGENT_IMAGE}"
    docker build -t "$AGENT_IMAGE" "$workdir/nanoclaw/container"

    # Push only when AGENT_IMAGE names a registry repo (has a / and isn't the
    # bare local default), so first boot can pull it.
    case "$AGENT_IMAGE" in
        */*)
            echo "==> Pushing agent image ${AGENT_IMAGE}"
            docker push "$AGENT_IMAGE"
            ;;
        *)
            echo "==> Agent image is local-only (${AGENT_IMAGE}); not pushing"
            ;;
    esac
}

build_sbx() {
    echo "==> Building sandbox image ${IMAGE}"
    echo "    inner images:"
    echo "      agent    = ${AGENT_IMAGE}"
    echo "      onecli   = ${ONECLI_IMAGE}"
    echo "      postgres = ${POSTGRES_IMAGE}"
    docker build -t "$IMAGE" \
        --build-arg NANOCLAW_REPO="$NANOCLAW_REPO" \
        --build-arg NANOCLAW_REF="$NANOCLAW_REF" \
        --build-arg AGENT_IMAGE="$AGENT_IMAGE" \
        --build-arg AGENT_TAG="$AGENT_TAG" \
        --build-arg ONECLI_IMAGE="$ONECLI_IMAGE" \
        --build-arg ONECLI_TAG="$ONECLI_TAG" \
        --build-arg POSTGRES_IMAGE="$POSTGRES_IMAGE" \
        --build-arg POSTGRES_TAG="$POSTGRES_TAG" \
        "$KIT_DIR"
}

case "$TARGET" in
    agent) build_agent ;;
    sbx)   build_sbx ;;
    all)   build_agent; build_sbx ;;
    *) echo "error: unknown TARGET '$TARGET' (want agent|sbx|all)" >&2; exit 1 ;;
esac

echo "==> Done"
