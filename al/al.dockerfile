# syntax=docker/dockerfile:1
# altool and the .NET runtimes it runs on, as an overlay.
#
# Nothing here reads a create-time value, so it is all build: no per-create
# download of a few hundred megabytes, a failure that surfaces at publish
# instead of in a user's sandbox, and no install-phase egress in al.yaml.
#
# Three choices worth knowing about:
#
#   * Runtime, not SDK. `dotnet tool install` needs the SDK, but altool itself
#     is framework-dependent on Microsoft.NETCore.App and
#     Microsoft.AspNetCore.App and nothing more, so the SDK lives only in the
#     build stage and the overlay ships the ASP.NET Core runtime (which carries
#     the base runtime with it) -- 8.0 and 10.0 side by side, so an altool
#     release on either major finds its framework.
#   * /opt/al, not ~/.dotnet. A mixin lands on an unknown base, and whatever is
#     at /home/agent may be a mounted volume; a kit-owned prefix outside the
#     agent's home cannot be covered or collide with a user's own ~/.dotnet.
#   * A wrapper, not PATH and DOTNET_ROOT exports. The tool's apphost finds its
#     runtime through DOTNET_ROOT, and a profile.d export reaches login shells
#     only -- not an MCP server an agent spawns directly. /usr/local/bin/al sets
#     DOTNET_ROOT for itself, so `al` works from any process with a normal PATH.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The kit's `version` arg, handed over by the descriptor. No default,
# deliberately: an empty value would let `dotnet tool install` float to the
# latest package while the descriptor went on publishing
# `al@<the version arg>`. The guard below fails instead.
ARG ALTOOL_VERSION

USER root

# The 8.0 and 10.0 channels float to their latest patch at build. That is a
# security property rather than drift: the kit's nightly rebuild picks up
# runtime servicing releases without a descriptor edit, and altool targets a
# major, which every patch of it satisfies. Both runtimes go into the one
# install dir; the host resolves whichever major the tool's runtimeconfig names.
#
# The SDK is 10.0 because an SDK refuses to install a tool targeting a newer
# framework than its own, and 10.0 installs 8.0 tools just as well. It goes to
# /tmp/sdk and is never staged; it exists to run
# `dotnet tool install`, which is what lays out the tool's apphost and .store
# tree. `--tool-path` rather than `--global` so that tree lands in the staging
# directory instead of the build user's home. The apphost references its
# entry assembly by relative path, so the tree relocates intact from
# /out/opt/al/tools to /opt/al/tools.
RUN <<EOF
set -eux
[ -n "${ALTOOL_VERSION}" ] || { echo "ALTOOL_VERSION must be set" >&2; exit 1; }
curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/dotnet-install.sh https://dot.net/v1/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /tmp/sdk --no-path
bash /tmp/dotnet-install.sh --channel 8.0 --runtime aspnetcore --install-dir /out/opt/al/dotnet --no-path
bash /tmp/dotnet-install.sh --channel 10.0 --runtime aspnetcore --install-dir /out/opt/al/dotnet --no-path
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
/tmp/sdk/dotnet tool install Microsoft.Dynamics.BusinessCentral.Development.Tools \
  --version "${ALTOOL_VERSION}" --tool-path /out/opt/al/tools
rm -rf /tmp/dotnet-install.sh
EOF

# The launcher. DOTNET_ROOT points the apphost at the runtime this overlay
# ships; it is set for the one process rather than exported into every shell,
# so it cannot redirect some other .NET install the base or the user has.
RUN <<'EOF'
set -eu
mkdir -p /out/usr/local/bin
cat > /out/usr/local/bin/al <<'SCRIPT'
#!/bin/sh
# Installed by the `al` sandbox kit: altool on the .NET runtime in /opt/al.
DOTNET_ROOT=/opt/al/dotnet
export DOTNET_ROOT
exec /opt/al/tools/al "$@"
SCRIPT
chmod 0755 /out/usr/local/bin/al
EOF

# `dotnet` on PATH, for the same reason the launcher is: /usr/local/bin reaches
# every process, a profile.d PATH export only login shells. A symlink suffices
# here -- the muxer resolves its own real path and finds the runtimes beside it,
# so it needs no DOTNET_ROOT. Relative, so it resolves both in the staging tree
# (which the gate below relies on) and once the overlay lands at /.
RUN ln -s ../../../opt/al/dotnet/dotnet /out/usr/local/bin/dotnet

# THE GATE. The descriptor publishes `al@<the version arg>`, so the build checks
# the installed package against it -- from the tool manifest, which records the
# NuGet version exactly, rather than from altool's own output, which formats its
# version differently. The package row is matched by its id and its version
# column compared whole, not as a substring.
#
# Both shipped runtime majors are then confirmed present, from the host's own
# list as reached through the staged `dotnet` symlink, so a channel that
# silently installed nothing, or a symlink that resolves nowhere, fails here.
#
# Then the staged tool is run once, through the wrapper path and against the
# staged runtime only (the SDK is deleted first), which is what proves the
# overlay is self-sufficient: a missing framework or an apphost that cannot find
# its runtime fails here, at build, instead of at the agent's first `al`.
RUN <<'EOF'
set -eu
installed="$(/tmp/sdk/dotnet tool list --tool-path /out/opt/al/tools \
  | awk 'tolower($1) == "microsoft.dynamics.businesscentral.development.tools" {print $2}')"
[ "$installed" = "${ALTOOL_VERSION}" ] || {
  echo "pin mismatch: kit declares ${ALTOOL_VERSION}, tool manifest reports '${installed}'" >&2
  exit 1
}
for major in 8 10; do
  /out/usr/local/bin/dotnet --list-runtimes \
    | grep -q "^Microsoft.AspNetCore.App ${major}\." || {
    echo "ASP.NET Core ${major}.0 runtime missing from /out/opt/al/dotnet" >&2
    exit 1
  }
done
rm -rf /tmp/sdk
DOTNET_ROOT=/out/opt/al/dotnet /out/opt/al/tools/al --version
EOF

# The tool install leaves its NuGet cache and CLI state under root's home;
# none of it is staged. Ownership is reset because an overlay's entries override
# the base's, and nothing under /opt/al should be writable by anyone but root.
RUN chown -R 0:0 /out

# The overlay: the runtimes and altool under /opt/al, and `al` and `dotnet` on
# PATH, landing on any base. No ENTRYPOINT -- the base workload's launch command
# stays, and the agent runs `al` from the shell.
FROM scratch
COPY --from=build /out /
