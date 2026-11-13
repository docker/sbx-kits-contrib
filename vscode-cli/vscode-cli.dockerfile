# syntax=docker/dockerfile:1
# The VS Code CLI, as an overlay.
#
# The CLI is a single static binary (the musl build, which runs on glibc bases
# too), so the overlay is just /usr/local/bin/code. Building it in means no
# download, and no install-phase egress, at sandbox create.
FROM alpine:3.22 AS build

ARG VSCODE_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl

RUN <<'EOF'
set -eux
[ -n "${VSCODE_VERSION}" ] || { echo "VSCODE_VERSION must be set" >&2; exit 1; }
case "${TARGETARCH:-amd64}" in
  amd64) arch=x64 ;;
  arm64) arch=arm64 ;;
  *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;;
esac
mkdir -p /out/usr/local/bin
curl -fsSL -o /tmp/cli.tar.gz \
  "https://update.code.visualstudio.com/${VSCODE_VERSION}/cli-alpine-${arch}/stable"
tar -xzf /tmp/cli.tar.gz -C /out/usr/local/bin code
reported="$(/out/usr/local/bin/code --version | awk 'NR == 1 { if ($1 == "code") print $2; else print $1 }')"
[ "$reported" = "${VSCODE_VERSION}" ] || {
  echo "pin mismatch: kit declares ${VSCODE_VERSION}, CLI reports '${reported}'" >&2
  exit 1
}
chown -R 0:0 /out
chmod 0755 /out/usr/local/bin/code
EOF

# The overlay: /usr/local/bin/code. No ENTRYPOINT -- the base workload's
# launch command stays.
FROM scratch
COPY --from=build /out /
