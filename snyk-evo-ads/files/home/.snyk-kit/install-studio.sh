#!/bin/sh
set -eu

case "$(uname -m)" in
  aarch64|arm64) studio_arch=arm64 ;;
  x86_64|amd64) studio_arch=x86_64 ;;
  *) echo "studio: ERROR unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# Resolve latest once so the binary and checksum come from the same release.
studio_release_url="$(curl -fsSL --max-time 30 -o /dev/null -w '%{url_effective}' \
  https://github.com/snyk/studio-recipes/releases/latest)"
case "$studio_release_url" in
  https://github.com/snyk/studio-recipes/releases/tag/v*) studio_tag="${studio_release_url##*/}" ;;
  *) echo "studio: ERROR could not resolve the latest release." >&2; exit 1 ;;
esac
studio_version="${studio_tag#v}"
printf '%s' "$studio_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "studio: ERROR unexpected release version." >&2; exit 1;
}
studio_asset="snyk-studio-${studio_version}-linux-${studio_arch}"
studio_base="https://github.com/snyk/studio-recipes/releases/download/$studio_tag"
studio_dir="$HOME/.local/share/snyk-studio"
mkdir -p "$studio_dir"
studio_tmp="$(mktemp -d "$studio_dir/download.XXXXXX")"
trap 'rm -f "$studio_tmp/binary" "$studio_tmp/checksums"; rmdir "$studio_tmp"' EXIT
for studio_file in "$studio_asset" checksums.txt; do
  if [ "$studio_file" = checksums.txt ]; then studio_dest=checksums; else studio_dest=binary; fi
  if curl -fsSL --max-time 120 "$studio_base/$studio_file" -o "$studio_tmp/$studio_dest"; then
    :
  else
    rc=$?
    echo "studio: ERROR download failed (curl exit $rc)." >&2
    exit "$rc"
  fi
done
studio_sha="$(awk -v asset="$studio_asset" '$2 == asset || $2 == "*" asset { print $1 }' "$studio_tmp/checksums")"
if [ "${#studio_sha}" -ne 64 ] || ! printf '%s' "$studio_sha" | grep -Eq '^[0-9a-fA-F]+$'; then
  echo "studio: ERROR missing or invalid release checksum." >&2
  exit 1
fi
printf '%s  %s\n' "$studio_sha" "$studio_tmp/binary" | sha256sum -c -
chmod 0755 "$studio_tmp/binary"
mv "$studio_tmp/binary" "$studio_dir/snyk-studio-installer"
echo "studio: $studio_version downloaded"

"$studio_dir/snyk-studio-installer" install -y --no-latest-deps
echo "studio: recipes installed"
