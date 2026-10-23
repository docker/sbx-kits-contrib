#!/usr/bin/env bash
# Copyright 2026 The Dapr Agents Sandbox Kit Authors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

DAPR_VERSION="1.18.2"
UV_VERSION="0.10.12"
INSTALL_ROOT="/home/agent/.local/share/dapr-kit"
BIN_ROOT="/home/agent/.dapr/bin"

apt-get update
apt-get install -y --no-install-recommends ca-certificates python3 python3-pip python3-venv tar
rm -rf /var/lib/apt/lists/*

python3 -m pip install --no-cache-dir --break-system-packages "uv==${UV_VERSION}"

case "$(dpkg --print-architecture)" in
  amd64)
    DAPR_ARCH="amd64"
    CLI_SHA256="ccfff008fd16f50096a9192ad56697ac7052e3add6fa0a07789d87b4c4df8c40"
    DAPRD_SHA256="5e9b01848d256f3ee931235d0d70e3cc97dd2b8e8f4d35b2abdc97d57195a188"
    ;;
  arm64)
    DAPR_ARCH="arm64"
    CLI_SHA256="356e40cffc3ee4ebaa0396edde31a6e33bc0351162a6a9ea98550baebb8d039f"
    DAPRD_SHA256="a6c0f1d1c25b1b90d48cf146b1e5073f43b8538b9aa17bd3a3d219da40bd3410"
    ;;
  *)
    echo "dapr-agents: unsupported architecture $(dpkg --print-architecture); amd64 and arm64 are supported" >&2
    exit 1
    ;;
esac

mkdir -p "${BIN_ROOT}" "${INSTALL_ROOT}"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

download_and_verify() {
  local url="$1" checksum="$2" output="$3"
  curl --fail --location --retry 3 --silent --show-error "$url" --output "$output"
  printf '%s  %s\n' "$checksum" "$output" | sha256sum --check --status
}

mkdir -p "${work_dir}/cli" "${work_dir}/runtime"
download_and_verify \
  "https://github.com/dapr/cli/releases/download/v${DAPR_VERSION}/dapr_linux_${DAPR_ARCH}.tar.gz" \
  "$CLI_SHA256" "${work_dir}/dapr-cli.tar.gz"
tar -xzf "${work_dir}/dapr-cli.tar.gz" -C "${work_dir}/cli"
install -m 0755 "${work_dir}/cli/dapr" /usr/local/bin/dapr

download_and_verify \
  "https://github.com/dapr/dapr/releases/download/v${DAPR_VERSION}/daprd_linux_${DAPR_ARCH}.tar.gz" \
  "$DAPRD_SHA256" "${work_dir}/daprd.tar.gz"
tar -xzf "${work_dir}/daprd.tar.gz" -C "${work_dir}/runtime"
install -m 0755 "${work_dir}/runtime/daprd" "${BIN_ROOT}/daprd"

dapr --version
"${BIN_ROOT}/daprd" --version
uv --version
chown -R agent:agent /home/agent/.dapr /home/agent/.local
