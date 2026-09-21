# syntax=docker/dockerfile:1.7
# The Task CLI as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to install anything, and the first v3 cut transcribed that hook faithfully.
# v3 lets a mixin carry an overlay, and this kit is the whole of what an overlay
# is for: one pinned, digest-verified release tarball holding one static Go
# binary, with nothing in it that exists only at sandbox-create time. Building
# it instead of installing it buys no per-create download, a binary whose digest
# is fixed in the published layer rather than re-verified in every sandbox, a
# failure that surfaces at publish rather than in a user's sandbox, and -- the
# one visible in the permission surface -- the disappearance of the kit's entire
# install phase, because the three GitHub hosts existed only so that hook could
# reach the network. See task.yaml.
#
# Nothing stays a hook here. There is no apt step, nothing reads a create-time
# value, nothing merges into a file the composed base also writes, and nothing
# lands in a path a volume or skills mount would cover -- so this kit empties
# rather than narrows, and task.yaml declares no lifecycle capability at all.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The pin the install hook carried, unchanged: the release version and the
# per-arch SHA256 of the asset. Bumping Task means editing this line, both
# digests, the `provides` entry in task.yaml and the README, together.
ARG TASK_VERSION=3.50.0
ARG TARGETARCH

USER root

# v2's one install hook, moved here.
#
# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- and asking dpkg is what made the kit require
# `deb/dpkg` of every base it composed onto, a requirement that goes with it.
# The case arms keep the dpkg vocabulary because TARGETARCH speaks it too.
#
# Digest-checked here exactly as it was there. The check has not become
# ceremonial by moving: it is what makes the published layer's content
# attributable to the upstream release rather than to whatever the release URL
# served on build day.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        tarball="task_linux_amd64.tar.gz"; \
        sha256=d449ba85ab85a0769989d78f8b9872938e4ba9347f7f4f925f73d98272a0a655 ;; \
      arm64) \
        tarball="task_linux_arm64.tar.gz"; \
        sha256=ee67e7d999a4a70711bff1946c70bf76628012c91d9be55626ee90ba976897da ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/task.tgz \
      "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/${tarball}"; \
    echo "${sha256}  /tmp/task.tgz" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -C /out/usr/local/bin -xzf /tmp/task.tgz task; \
    rm /tmp/task.tgz; \
    chmod 0755 /out/usr/local/bin/task; \
    # The release tarball records the publisher's CI uid, and tar preserves it:
    # as image content on an unknown base that id may be a real account, and a
    # file's owner can rewrite it whatever its mode says.
    chown 0:0 /out/usr/local/bin/task; \
    # The pin is a claim about content, so the build enforces it. The digest
    # already ties the bytes to the published asset; this ties the published
    # asset to the number in `provides`, which is the part a re-cut or
    # mislabelled release would break. `task --version` prints the bare number
    # and nothing else (`3.50.0`), so the whole first line is compared, with a
    # leading `v` stripped in case a future release restores the tag spelling
    # -- SPEC-v3 §5.2 admits no `v` prefix in a version. The comparison is
    # exact rather than a substring match on purpose: if upstream changes the
    # format, this should fail loudly and be re-read, not quietly keep passing.
    reported="$(/out/usr/local/bin/task --version)"; \
    echo "task --version: ${reported}"; \
    installed="$(printf '%s\n' "${reported}" | head -1 | tr -d '[:space:]')"; \
    [ "${installed#v}" = "${TASK_VERSION}" ] || { \
      echo "pin mismatch: kit declares ${TASK_VERSION}, task reports '${reported}'" >&2; \
      exit 1; \
    }

# The overlay: one binary, landing on any base. Nothing is staged under the
# agent's home -- /usr/local is what a mixin landing on an unknown base should
# prefer, since whatever is at /home/agent may be a mounted volume. No
# ENTRYPOINT -- the base workload's launch command stays, and the agent runs
# `task` from the shell.
FROM scratch
COPY --from=build /out /
