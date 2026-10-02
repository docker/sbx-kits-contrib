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
# Components, not exactly three: upstream has shipped four-part versions such as
# v0.6.5.2, and this check only guards what goes into a URL.
printf '%s' "$scan_version" | grep -Eq '^[0-9]+(\.[0-9]+)+$' || {
  echo "agent-scan: ERROR unexpected release version." >&2; exit 1;
}
scan_base="https://github.com/snyk/agent-scan/releases/download/$scan_tag"
scan_dir="$HOME/.local/share/snyk-agent-scan"
mkdir -p "$scan_dir"
scan_tmp="$(mktemp -d "$scan_dir/download.XXXXXX")"
trap 'rm -f "$scan_tmp/binary" "$scan_tmp/checksums"; rmdir "$scan_tmp"' EXIT

# checksums.txt first, because the asset NAME is read back from it rather than
# built from the tag. The two do not always agree: release v0.6.7 (2026-09-28)
# shipped binaries still named agent-scan-0.6.6-* next to an sbom-0.6.7.json,
# which 404s every URL derived from the tag and broke this install outright.
# The release's own manifest is the only thing that knows what it actually
# contains, so reading the name from it survives that drift in either
# direction. It is fetched from $scan_base, so binary and checksum still come
# from the one release.
if curl -fsSL --max-time 120 "$scan_base/checksums.txt" -o "$scan_tmp/checksums"; then
  :
else
  rc=$?
  echo "agent-scan: ERROR checksums download failed (curl exit $rc)." >&2
  exit "$rc"
fi

# Strip "<sha>  " and the optional binary-mode "*", then keep only assets for
# this OS/arch. Anchored, and the version part is digits and dots only, so a
# hostile or corrupt manifest cannot smuggle a path or an option into the URL
# and filename this name is about to be used as.
scan_asset="$(sed 's/^[0-9a-fA-F]*[[:space:]][[:space:]]*\**//' "$scan_tmp/checksums" \
  | grep -E "^agent-scan-[0-9][0-9.]*-linux-${scan_arch}$" | sort -u)"
case "$scan_asset" in
  '')
    echo "agent-scan: ERROR release $scan_tag lists no linux-$scan_arch asset." >&2
    exit 1 ;;
  *"
"*)
    echo "agent-scan: ERROR release $scan_tag lists more than one linux-$scan_arch asset." >&2
    exit 1 ;;
esac

if curl -fsSL --max-time 120 "$scan_base/$scan_asset" -o "$scan_tmp/binary"; then
  :
else
  rc=$?
  echo "agent-scan: ERROR download failed (curl exit $rc)." >&2
  exit "$rc"
fi
scan_sha="$(awk -v asset="$scan_asset" '$2 == asset || $2 == "*" asset { print $1 }' "$scan_tmp/checksums")"
if [ "${#scan_sha}" -ne 64 ] || ! printf '%s' "$scan_sha" | grep -Eq '^[0-9a-fA-F]+$'; then
  echo "agent-scan: ERROR missing or invalid release checksum." >&2
  exit 1
fi
printf '%s  %s\n' "$scan_sha" "$scan_tmp/binary" | sha256sum -c -
chmod 0755 "$scan_tmp/binary"
mv "$scan_tmp/binary" "$scan_dir/agent-scan"
echo "agent-scan: standalone $scan_asset installed from release $scan_tag"
