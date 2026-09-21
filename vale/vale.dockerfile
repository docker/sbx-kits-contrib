# syntax=docker/dockerfile:1.7
# The Vale prose linter as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to install anything, and the first v3 cut transcribed that hook faithfully.
# v3 lets a mixin carry an overlay, and this install is exactly what an overlay
# is for: one pinned, digest-verified release tarball holding one static Go
# binary, with nothing in it that exists only at sandbox-create time. Building
# it instead of installing it buys no per-create download, a binary whose digest
# is fixed in the published layer rather than re-verified in every sandbox, a
# failure that surfaces at publish rather than in a user's sandbox, and the
# removal of the kit's install-phase network grant, which existed only so that
# hook could reach GitHub.
#
# WHAT DOES NOT GO WITH IT, and this is the part to read before trimming
# vale.yaml's policy further: the *runtime* grant for the same three GitHub
# hosts stays. `vale sync` fetches the style packages a .vale.ini references
# from GitHub releases, from the agent's steady state, long after any install
# phase has closed. The two grants looked identical and were never the same
# thing; moving the install is what makes that visible.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The pin the install hook carried, unchanged: the release version and the
# per-arch SHA256 of the asset, sourced from the release's checksums.txt.
# Bumping Vale means editing this line, both digests, the `provides` entry in
# vale.yaml and the README, together.
#
# We deliberately do NOT query api.github.com for `releases/latest`:
# unauthenticated API calls from shared CI runner IPs hit the 60-req/hr rate
# limit and 403, which made installs flaky. Pinning by version + SHA256, in the
# kit, in git, is also the safer supply chain -- and now that this runs at
# build, a bad release is a red build rather than a sandbox that fails to come
# up in front of a user.
ARG VALE_VERSION=3.14.2
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
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        tarball="vale_${VALE_VERSION}_Linux_64-bit.tar.gz"; \
        sha256=469cf88ec58a374dca14b2564c4391d2c9a1c632210aa0b642758b794082e05f ;; \
      arm64) \
        tarball="vale_${VALE_VERSION}_Linux_arm64.tar.gz"; \
        sha256=b11fa9955b93814f993442568b9b922604cc4b574643037b84900e9514860802 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/vale.tgz \
      "https://github.com/vale-cli/vale/releases/download/v${VALE_VERSION}/${tarball}"; \
    echo "${sha256}  /tmp/vale.tgz" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -C /out/usr/local/bin -xzf /tmp/vale.tgz vale; \
    rm /tmp/vale.tgz; \
    chmod 0755 /out/usr/local/bin/vale; \
    # The release tarball records the publisher's CI uid, and tar preserves it:
    # as image content on an unknown base that id may be a real account, and a
    # file's owner can rewrite it whatever its mode says.
    chown 0:0 /out/usr/local/bin/vale; \
    # The pin is a claim about content, so the build enforces it. The digest
    # already ties the bytes to the published asset; this ties the published
    # asset to the number in `provides`, which is the part a re-cut or
    # mislabelled release would break. `vale --version` prints
    # `vale version 3.14.2`, so the number is the last field of the first line,
    # with a leading `v` stripped -- SPEC-v3 §5.2 admits no `v` prefix in a
    # version. Exact rather than a substring match on purpose: if upstream
    # changes the format this should fail loudly and be re-read, not quietly
    # keep passing.
    reported="$(/out/usr/local/bin/vale --version)"; \
    echo "vale --version: ${reported}"; \
    installed="$(printf '%s\n' "${reported}" | awk 'NR==1{print $NF}')"; \
    [ "${installed#v}" = "${VALE_VERSION}" ] || { \
      echo "pin mismatch: kit declares ${VALE_VERSION}, vale reports '${reported}'" >&2; \
      exit 1; \
    }

# The overlay: one binary, landing on any base. Nothing is staged under the
# agent's home -- /usr/local is what a mixin landing on an unknown base should
# prefer, since whatever is at /home/agent may be a mounted volume, and vale's
# own state (the styles `vale sync` downloads) belongs to the workspace and the
# agent, not to this layer. No ENTRYPOINT -- the base workload's launch command
# stays, and the agent runs `vale` from the shell.
FROM scratch
COPY --from=build /out /
