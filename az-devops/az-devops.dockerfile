# syntax=docker/dockerfile:1
# libsecret for the Azure DevOps MCP, as an overlay.
#
# `npx @azure-devops/mcp` pulls in keytar, a native addon linked against
# libsecret-1.so.0. The sandbox-templates bases ship neither libsecret nor the
# glib it depends on, so the MCP dies at load with ERR_DLOPEN_FAILED. Building
# the library into the overlay means no apt run, and no install-phase egress to
# the Ubuntu mirrors, at sandbox create.
#
# The overlay carries exactly the packages apt had to add on top of the base:
# libsecret-1-0 plus whichever of its dependencies (glib and friends) the base
# lacks. Packages the base already has are left to the base.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER root

RUN <<'EOF'
set -eux
dpkg-query -W -f '${Package}\n' | sort > /tmp/before
apt-get update
apt-get install -y --no-install-recommends libsecret-1-0
dpkg-query -W -f '${Package}\n' | sort > /tmp/after
comm -13 /tmp/before /tmp/after > /tmp/added
cat /tmp/added
grep -qx 'libsecret-1-0' /tmp/added

# Stage every file (and symlink) of the added packages, minus docs. Paths
# under the usrmerge symlinks (/lib, /bin, ...) are rewritten to /usr so the
# overlay never replaces a base symlink with a real directory.
mkdir -p /out
xargs dpkg -L < /tmp/added | sort -u | while read -r f; do
  [ -d "$f" ] && [ ! -L "$f" ] && continue
  [ -e "$f" ] || [ -L "$f" ] || continue
  case "$f" in
    /usr/share/doc/*|/usr/share/man/*|/usr/share/lintian/*) continue ;;
    /lib/*|/lib64/*|/bin/*|/sbin/*) dest="/out/usr$f" ;;
    *) dest="/out$f" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp -P "$f" "$dest"
done
rm -rf /var/lib/apt/lists/*
EOF

# THE GATE. Every library libsecret needs must resolve from the base plus the
# staged files alone; otherwise the overlay would fail at the MCP's first
# start instead of here.
FROM ${BASE_IMAGE} AS verify
USER root
COPY --from=build /out /
RUN <<'EOF'
set -eu
ldconfig
lib="$(ldconfig -p | awk '/libsecret-1\.so\.0 /{print $NF; exit}')"
[ -n "$lib" ] || { echo "libsecret-1.so.0 not in the linker cache" >&2; exit 1; }
if ldd "$lib" | grep 'not found'; then exit 1; fi
touch /verified
EOF

FROM build AS stage
COPY --from=verify /verified /tmp/verified
RUN chown -R 0:0 /out

# The overlay: libsecret and its missing dependencies under /usr. No
# ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=stage /out /
