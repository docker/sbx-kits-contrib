# syntax=docker/dockerfile:1
# The pinned JFrog CLI is portable content, so v3 carries it in an overlay
# rather than downloading it during every sandbox create.
FROM dhi.io/debian-base:trixie-dev AS build
ARG TARGETARCH
ARG JF_VERSION

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Version and per-architecture SHA256 are preserved from the v2 install hook.
# To bump: update JF_VERSION, both hashes, the descriptor version/provide, and
# the README. The raw binary URLs are:
# https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/<version>/jfrog-cli-linux-<arch>/jf
RUN set -eu; \
    [ -n "${JF_VERSION}" ] || { echo "JF_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) sha256="7d9fcfd1d21d779cf18e96a0ae97706c6d15808ff79a8fa1b91f046d0fd419ca" ;; \
      arm64) sha256="1858ad5e2acfcaecb5da5b5f623cd667b85cce33b59181d60384dc5f42908351" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    url="https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${JF_VERSION}/jfrog-cli-linux-${TARGETARCH}/jf"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/jf "${url}"; \
    echo "${sha256}  /tmp/jf" > /tmp/jf.sha256; \
    sha256sum -c /tmp/jf.sha256; \
    mkdir -p /out/usr/local/bin; \
    install -m 0755 -o 0 -g 0 /tmp/jf /out/usr/local/bin/jf-real; \
    output="$(/out/usr/local/bin/jf-real --version)"; \
    printf '%s\n' "${output}"; \
    printf '%s\n' "${output}" > /tmp/jf-version-output; \
    tr -s ' ,():\t' '\n' < /tmp/jf-version-output > /tmp/jf-version-tokens; \
    grep -Fxq "${JF_VERSION}" /tmp/jf-version-tokens

# JF_URL was a v2 environment value formed from the create-time host arg.
# A v3 overlay cannot bake that per-install value into image config, so this
# wrapper recreates it for every CLI invocation while keeping the public `jf`
# command unchanged.
RUN <<'EOF'
cat > /out/usr/local/bin/jf <<'SH'
#!/bin/sh
: "${JFROG_HOST:?JFROG_HOST is required}"
export JF_URL="https://${JFROG_HOST}"
exec /usr/local/bin/jf-real "$@"
SH
chmod 0755 /out/usr/local/bin/jf
EOF

# The overlay: no entrypoint, so the base workload keeps its launch command.
FROM scratch
COPY --from=build /out /
ENV JFROG_CLI_OFFER_CONFIG=false \
    JFROG_CLI_AVOID_NEW_VERSION_WARNING=true
