#!/bin/sh
set -eu

case "$(uname -m)" in
  aarch64|arm64) scan_arch=arm64 ;;
  x86_64|amd64) scan_arch=x86_64 ;;
  *) echo "agent-scan: ERROR unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# Resolve latest once so the binary and checksum come from the same release.
scan_release_url="$(curl -fsSL --max-time 30 -o /dev/null -w '%{url_effective}' \
  https://github.com/snyk/agent-scan/releases/latest)"
case "$scan_release_url" in
  https://github.com/snyk/agent-scan/releases/tag/v*) scan_tag="${scan_release_url##*/}" ;;
  *) echo "agent-scan: ERROR could not resolve the latest release." >&2; exit 1 ;;
esac
scan_version="${scan_tag#v}"
printf '%s' "$scan_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "agent-scan: ERROR unexpected release version." >&2; exit 1;
}
scan_asset="agent-scan-${scan_version}-linux-${scan_arch}"
scan_base="https://github.com/snyk/agent-scan/releases/download/$scan_tag"
scan_dir="$HOME/.local/share/snyk-agent-scan"
mkdir -p "$scan_dir"
scan_tmp="$(mktemp -d "$scan_dir/download.XXXXXX")"
trap 'rm -f "$scan_tmp/binary" "$scan_tmp/checksums"; rmdir "$scan_tmp"' EXIT
for scan_file in "$scan_asset" checksums.txt; do
  if [ "$scan_file" = checksums.txt ]; then scan_dest=checksums; else scan_dest=binary; fi
  if curl -fsSL --max-time 120 "$scan_base/$scan_file" -o "$scan_tmp/$scan_dest"; then
    :
  else
    rc=$?
    echo "agent-scan: ERROR download failed (curl exit $rc)." >&2
    exit "$rc"
  fi
done
scan_sha="$(awk -v asset="$scan_asset" '$2 == asset || $2 == "*" asset { print $1 }' "$scan_tmp/checksums")"
if [ "${#scan_sha}" -ne 64 ] || ! printf '%s' "$scan_sha" | grep -Eq '^[0-9a-fA-F]+$'; then
  echo "agent-scan: ERROR missing or invalid release checksum." >&2
  exit 1
fi
printf '%s  %s\n' "$scan_sha" "$scan_tmp/binary" | sha256sum -c -
chmod 0755 "$scan_tmp/binary"
mv "$scan_tmp/binary" "$scan_dir/agent-scan"
echo "agent-scan: standalone $scan_version installed"
