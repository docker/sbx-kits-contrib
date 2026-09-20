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

# npm's bin entry resolves node through `#!/usr/bin/env node`, so the overlay
# carries a node for bases that have none. A base that already has one keeps
# whichever PATH finds first; both run the same package.
cp -a "$(command -v node)" /out/usr/local/bin/node
EOF

# No profile.d snippet: v2 declared no `environment.variables` for this kit,
# and the provider configuration rides the descriptor's lifecycle `files:`
# entry rather than the image.

# The overlay: the agent as the template ships it, landing on any base.
FROM scratch
COPY --from=build /out /
