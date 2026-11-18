# syntax=docker/dockerfile:1
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build
USER root
ARG TARGETARCH
ARG AGENTMEMORY_VERSION=0.9.33
ARG NODE_VERSION=24.22.2
ARG III_VERSION=0.25.1
ARG STATE_WORKER_VERSION=0.22.22
ARG HTTP_WORKER_VERSION=0.22.8

RUN <<EOF
set -eu
case "${TARGETARCH}" in
  amd64)
    node_arch=x64
    target=x86_64-unknown-linux-gnu
    node_sha=361718c444e49af2ca5a110c83ba6a8901143f23ab285ebbef0341f391f482a9
    iii_sha=0f486f0fb175013fdebd482735228a47de5fd5014d375a9720cb4f958341208a
    state_sha=dcbe2dbf51809be455361421625fc3f07995c5ec6103e8de42bf41830b51e61d
    http_sha=f7959f90392338251e9a087b2bc004d9a53204ec7b08e9d913f8e29f0efb4569
    ;;
  arm64)
    node_arch=arm64
    target=aarch64-unknown-linux-gnu
    node_sha=95c264150aceb7f3437a29fd6984924f5f8d1511ea3cbd6c508b83f6c555dae2
    iii_sha=5938c6d2f25df8e301c058ef0bcfc9f858840c8b77d3eff1fa1bc83f67bd136c
    state_sha=11327ae5ced04139b328afb972c3c6762540143300c48052eecab615ae28f1d3
    http_sha=b6ef2dce652e3a5618b5ad709bcbf5219f10f62970c76701e592bb96ededdac4
    ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

opt=/out/opt/agentmemory-sbx
dl=$(mktemp -d)
mkdir -p "$opt/node/bin" "$opt/bin" "$opt/workers" "$dl/node"

fetch() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$1" "$2"
  echo "$3  $1" | sha256sum -c -
}

fetch "$dl/node.tgz" "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.gz" "$node_sha"
tar -xzf "$dl/node.tgz" -C "$dl/node" --strip-components=1
install -m 0755 "$dl/node/bin/node" "$opt/node/bin/node"
install -m 0644 "$dl/node/LICENSE" "$opt/node/LICENSE"

fetch "$dl/iii.tgz" "https://github.com/iii-hq/iii/releases/download/iii/v${III_VERSION}/iii-${target}.tar.gz" "$iii_sha"
tar -xzf "$dl/iii.tgz" -C "$dl" iii
install -m 0755 "$dl/iii" "$opt/bin/iii"

fetch "$dl/state.tgz" "https://api.workers.iii.dev/download/state/${STATE_WORKER_VERSION}/${target}" "$state_sha"
tar -xzf "$dl/state.tgz" -C "$dl" state
install -m 0755 "$dl/state" "$opt/workers/state"

fetch "$dl/http.tgz" "https://api.workers.iii.dev/download/http/${HTTP_WORKER_VERSION}/${target}" "$http_sha"
tar -xzf "$dl/http.tgz" -C "$dl" http
install -m 0755 "$dl/http" "$opt/workers/http"

PATH="$dl/node/bin:$PATH" npm install --prefix "$opt/runtime" \
  --omit=dev --omit=optional --ignore-scripts --no-audit --no-fund --no-package-lock \
  "@agentmemory/agentmemory@${AGENTMEMORY_VERSION}"

installed=$("$opt/node/bin/node" -p 'require(process.argv[1]).version' "$opt/runtime/node_modules/@agentmemory/agentmemory/package.json")
[ "$installed" = "${AGENTMEMORY_VERSION}" ] || { echo "agentmemory $installed != ${AGENTMEMORY_VERSION}" >&2; exit 1; }
"$opt/bin/iii" --version | grep -q "${III_VERSION}" || { echo "iii is not ${III_VERSION}" >&2; exit 1; }

rm -rf "$dl"
EOF

COPY files/ /out/
RUN chmod 0755 /out/usr/local/bin/agentmemory-sbx \
 && chmod 0644 /out/opt/agentmemory-sbx/start.sh /out/opt/agentmemory-sbx/register-mcp.sh \
 && chown -R 0:0 /out/opt /out/usr

FROM ${BASE_IMAGE} AS verified
USER root
COPY --from=build /out /out
COPY --from=build /out /
USER agent
RUN --network=none test "$(/usr/local/bin/agentmemory-sbx --version)" = "0.9.33"

FROM scratch
COPY --from=verified /out /
