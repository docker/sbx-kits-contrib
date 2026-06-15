#!/bin/sh
# Seed the sandbox's inner Docker daemon with the images NanoClaw needs at
# runtime (nanoclaw-agent, OneCLI gateway, postgres) by pulling them from
# their registries on first boot. The kit's spec.yaml already opens egress
# to those registries; the refs are digest-pinned so what runs is exactly
# what policy/scanning/signing can point at.
#
# Replaces the earlier approach of embedding a multi-GB `docker save` tar in
# the sandbox image (opaque to tooling, stored twice per sandbox, arch-
# specific). First boot pulls (~tens of seconds, in the background);
# subsequent boots no-op because the images are already present.
#
# The pin list is baked into the image at /opt/nanoclaw/inner-images.txt,
# one entry per line: "<pull-ref> <local-tag>". Each ref is pulled by
# digest, then tagged to the name NanoClaw/OneCLI expect (e.g. the
# CONTAINER_IMAGE override resolves nanoclaw-agent:latest).
#
# Safe to call concurrently: one caller seeds, the rest wait on the lock.

MANIFEST=/opt/nanoclaw/inner-images.txt
LOCK=/tmp/nanoclaw-seed-images.lock

[ -f "$MANIFEST" ] || exit 0

i=0
until docker info >/dev/null 2>&1; do
    sleep 1
    i=$((i+1))
    if [ $i -ge 60 ]; then
        echo "Docker daemon not ready after 60s" >&2
        exit 1
    fi
done

# Already seeded? (checks the local tag of every manifest entry)
seeded=1
while read -r ref tag; do
    [ -n "$ref" ] || continue
    case "$ref" in \#*) continue ;; esac
    docker image inspect "${tag:-$ref}" >/dev/null 2>&1 || { seeded=0; break; }
done < "$MANIFEST"
[ "$seeded" -eq 1 ] && exit 0

if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
    echo "First boot: pulling inner images from their registries..." >&2
    while read -r ref tag; do
        [ -n "$ref" ] || continue
        case "$ref" in \#*) continue ;; esac
        tag="${tag:-$ref}"
        if docker image inspect "$tag" >/dev/null 2>&1; then
            continue
        fi
        echo "  pulling $ref" >&2
        docker pull "$ref" >&2 || { echo "failed to pull $ref" >&2; exit 1; }
        # Tag the digest-pinned ref to the name the agent expects.
        [ "$ref" = "$tag" ] || docker tag "$ref" "$tag"
    done < "$MANIFEST"
else
    echo "Waiting for image seed started by another process..." >&2
    i=0
    while [ -d "$LOCK" ]; do
        sleep 2
        i=$((i+1))
        if [ $i -ge 300 ]; then
            echo "Timed out waiting for image seed" >&2
            exit 1
        fi
    done
    docker image inspect nanoclaw-agent:latest >/dev/null 2>&1 || exit 1
fi
