# syntax=docker/dockerfile:1
# OpenCode-on-Docker-Model-Runner as an overlay.
#
# There is no install to relocate here, because this kit never ran one: its v2
# content was a published template that already ships OpenCode. The template is
# therefore the distribution, and the overlay copies out of it -- the shape the
# devin mixin uses for the same reason.
#
# The copy preserves absolute paths rather than relocating into /opt. npm's
# global bin entry is a symlink relative to the global node_modules, and
# leaving both where the template put them is what keeps it resolving with no
# launcher shim to write and no guess about whether the postinstall left a
# native binary or a node script at the other end. `npm prefix -g` and
# `npm root -g` are asked at build time rather than hardcoded, so a template
# that moves its prefix does not silently produce an empty overlay.
#
# The consequence to know about: the overlay writes into the composed base's
# own global node_modules. That is the same place the base's npm would install
# to, so a base already carrying an `opencode-ai` there loses it to this one.
FROM docker/sandbox-templates:opencode-docker AS build

# Root for the staging step, which is the whole of this stage: / is root-owned
# and the template's default user is the unprivileged `agent` (uid 1000), so
# /out cannot be created. Unlike the sibling opencode mixin there is no install
# here to keep unprivileged -- the template already ran it.
USER root

RUN <<'EOF'
set -eux

prefix="$(npm prefix -g)"
root="$(npm root -g)"

# Fail loudly rather than shipping an overlay with nothing in it: if a future
# template installs OpenCode somewhere else, this is the line that says so.
test -d "$root/opencode-ai"
test -L "$prefix/bin/opencode" || test -f "$prefix/bin/opencode"

# The same binary the workload runs, verified before it is copied.
opencode --version

mkdir -p "/out${root}" "/out${prefix}/bin" /out/usr/local/bin
cp -a "$root/opencode-ai" "/out${root}/opencode-ai"
cp -a "$prefix/bin/opencode" "/out${prefix}/bin/opencode"

# No node is copied out. npm's bin entry is a symlink to a native ELF that
# links only libc, libpthread and libdl, so the overlay needs no runtime --
# verified by composing the sibling opencode overlay onto a node-free
# ubuntu:24.04, where `opencode --version` answers. Copying the template's node
# would also be worse than useless: Debian's /usr/bin/node is a small launcher
# linked against libnode.so.127, which a bare copy cannot resolve, and
# /usr/local/bin precedes /usr/bin on PATH -- so it would shadow a working node
# on any base that has one with a broken one.

# `mkdir -p` above created every missing level as root, which is what /usr,
# /usr/local, /usr/local/share and /usr/local/bin are in the template -- but
# it is not what the npm prefix is. The template hands the agent its global
# prefix so `npm install -g` works unprivileged, and an overlay's directory
# entries override the base's, so shipping the prefix root-owned would take
# the composed base's global npm prefix away from the user that installs into
# it. The chown therefore starts exactly at the prefix and no level above it.
# Numeric because scratch carries no /etc/passwd for a name to resolve
# against; 1000:1000 is the platform floor's `agent`, and it is the ownership
# `cp -a` just preserved on the copied tree.
chown -R 1000:1000 "/out${prefix}"
EOF

# No profile.d snippet: v2 declared no `environment.variables` for this kit,
# and the provider configuration rides the descriptor's lifecycle `files:`
# entry rather than the image.

# The overlay: the agent as the template ships it, landing on any base.
FROM scratch
COPY --from=build /out /
