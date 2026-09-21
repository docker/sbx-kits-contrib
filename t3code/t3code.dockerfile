# syntax=docker/dockerfile:1
# T3 Code's `t3` CLI as an overlay.
#
# This kit had no recipe at all until now. v2 mixins could carry no content,
# so both of its jobs -- the build toolchain and the `t3` package -- had to be
# create-time install hooks, and the first v3 cut transcribed that faithfully.
# v3 lets a mixin carry an overlay, and only one of the two jobs belongs in
# one:
#
#   * `t3` is pure content. `npm install -g` reads nothing that exists only at
#     sandbox-create time, and the point of this kit, stated in its own agent
#     context, is that `t3` being already on PATH keeps T3 Code's first
#     connection off the npm registry. Building it serves that better than a
#     hook does: the work happens once at publish instead of once per sandbox,
#     registry.npmjs.org leaves the kit's permission surface entirely, and the
#     package is digest-pinned in a layer that can be scanned.
#   * The toolchain stays a create-time hook, in t3code.yaml. It is apt, and
#     apt in a mixin cannot be baked: an overlay carries files, not dpkg
#     state, so packages installed here would arrive on the composed base with
#     no entry in its package database and without the shared-library closure
#     apt would have pulled in. The kit's context file also promises the
#     toolchain is *present in the sandbox*, for any later `npm install` or
#     `npm rebuild` that touches node-pty -- a promise only a hook can keep.
#
# The toolchain is still needed HERE, which is why this stage installs it too:
# it never reaches the overlay, because the overlay copies out one directory
# and dpkg's work is not in it.
#
# The base is the image family the kit documents as its target -- Node >= 18
# with npm, which every standard agent template ships. A mixin has no
# `sandbox.image` of its own to carry over, so this names the same template
# the rest of the repo builds its overlays on.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN. The kit's `version` arg arrives as this build arg: t3code.yaml
# validates its shape and expands the same value into `provides` and into its own
# `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an empty
# fallback would install `t3@` -- which npm reads as the latest dist-tag -- while
# the descriptor went on asserting a number. A missing value fails the build
# instead; see the guard below.
ARG T3_VERSION

USER root

# The toolchain, verbatim from the hook it duplicates (t3code.yaml's first
# install hook) -- same three packages, same DEBIAN_FRONTEND, same list
# cleanup. It is not `--no-install-recommends`-trimmed for the same reason:
# what compiles here should be what compiles in the sandbox.
#
# It is genuinely required. node-pty's install script is
# `node scripts/prebuild.js || node-gyp rebuild`, and there is no Linux
# prebuild, so the fallback runs -- verified by building this both ways:
# without g++/make/python3 the compile fails, npm records node-pty as a failed
# OPTIONAL dependency, drops its whole parent package with it, and STILL EXITS
# 0 with `added 1 package`. See the gate below.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y g++ make python3; \
    rm -rf /var/lib/apt/lists/*

# THE NPM INSTALL, MOVED OUT OF THE LIFECYCLE HOOK.
#
# Differences from the hook body, and why:
#
#   - `--prefix /opt/t3` instead of the base's global prefix. This install
#     relocates cleanly -- the package's bin entry is a launcher script that
#     resolves its payload relative to itself -- so the overlay can land in a
#     directory it owns outright rather than writing into whatever npm prefix
#     the composed base configured. It also keeps everything this kit ships
#     out of /home, which a mixin landing on an unknown base should prefer
#     anyway: whatever is at /home/agent there may be a mounted volume that
#     covers the overlay at create.
#   - No npm proxy configuration. The hook set proxy/https-proxy from
#     HTTP_PROXY and HTTPS_PROXY because a sandbox reaches the registry
#     through the sandbox's forced proxy; a build reaches it directly, and
#     BuildKit passes the builder's own proxy settings through when there is
#     one.
#   - No `command -v npm` guard. That check existed to turn "this base has no
#     Node" into a legible error at sandbox create; here the base is this
#     recipe's own choice and npm is simply present.
#   - `--include=optional` restates npm's own default so that an inherited
#     `omit=optional` -- from an .npmrc or from NPM_CONFIG_OMIT -- cannot
#     quietly produce the empty-install failure described above.
#
# AND NOW PINNED, where the hook asked for `t3@latest`. The version spec is
# exact -- `t3@0.0.42`, never a range or a dist-tag -- so what npm resolves is
# what the descriptor promised, and `provides: ["t3@<version>"]` describes the
# overlay rather than guessing at it.
#
# THE GATE, in three parts, because this package fails silently in two ways and
# the pin needs proving on top of that:
#
#   - `test -d` catches the optional-dependency cascade: npm exits 0 having
#     installed the launcher and nothing to launch. The kit's README describes
#     that failure mode from the hook era -- "the install command still exits 0
#     in some failure modes, leaving no t3 executable behind, and T3 Code reports
#     nothing more specific than a connection timeout". At build it is a red
#     build instead of a broken sandbox, which is most of the reason to move this
#     install here at all.
#   - `t3 --version` proves the platform binary runs on this architecture.
#   - Comparing what it prints against the pin is what makes the provide
#     trustworthy rather than merely requested: the descriptor publishes
#     `t3@${T3_VERSION}`, so an install that resolved to something else would
#     ship an overlay whose provide lies about its own content -- the one failure
#     mode worse than floating. It also covers a gap the npm version alone leaves
#     here, since what actually runs is the platform binary from an optional
#     dependency rather than the package npm resolved. `t3 --version` prints
#     `t3 v<version>`, so the second field is the number to match with its `v`
#     stripped -- the descriptor's value carries none, because SPEC-v3 §5.2
#     admits no `v` prefix in a version.
RUN set -eux; \
    [ -n "$T3_VERSION" ] || { echo "T3_VERSION must be set" >&2; exit 1; }; \
    npm install -g --prefix /opt/t3 --include=optional "t3@${T3_VERSION}"; \
    test -d /opt/t3/lib/node_modules/t3/node_modules/@t3code; \
    reported="$(/opt/t3/bin/t3 --version)"; \
    echo "t3 --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $2}')"; \
    [ "${installed#v}" = "$T3_VERSION" ] || { \
      echo "pin mismatch: descriptor says $T3_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

# The staged tree: the install prefix and one shim, nothing under /home.
#
# The shim is a symlink in /usr/local/bin rather than a PATH export in
# /etc/profile.d: /usr/local/bin is on PATH on every base and in every kind of
# shell, and T3 Code's remote bootstrap resolves `t3` from a non-login shell.
# That resolution is the whole job -- the bootstrap falls back to
# `npx --package t3@latest` when it finds nothing, which is exactly the
# registry round trip this kit exists to avoid.
#
# Ownership is explicit rather than inherited: root, which is what /opt and
# /usr/local/bin are on any base, and numeric because `scratch` carries no
# /etc/passwd for a name to resolve against.
RUN set -eux; \
    mkdir -p /out/opt /out/usr/local/bin; \
    cp -a /opt/t3 /out/opt/t3; \
    chown -R 0:0 /out/opt /out/usr/local/bin; \
    ln -s /opt/t3/bin/t3 /out/usr/local/bin/t3

# WHAT THIS OVERLAY CANNOT CARRY. Two things, both verified by composing the
# built overlay onto bases that are not this one:
#
#   - A Node runtime. The package's bin entry is `#!/usr/bin/env node`, so the
#     composed base must have node on PATH. The kit already required that of
#     its base, since the hook this replaces needed npm there.
#   - The platform binary's own shared libraries. Upstream's
#     @t3code/t3-linux-<arch>/t3 links libatomic, libstdc++, libgcc_s, libm,
#     libdl, libpthread and libc, and on node:22-slim, on a bare
#     ubuntu:24.04 + nodejs, and on this kit's own template base the binary
#     stops at "libatomic.so.1: cannot open shared object file". Adding
#     libatomic1 is enough: `t3 --version` then reports the pinned release.
#
#     CORRECTION, and it matters for what the descriptor has to keep doing:
#     this note used to claim every sandbox template carries all of them. They
#     do not. `libatomic.so.1` is in none of them -- checked by ldconfig on
#     docker/sandbox-templates:shell-docker, which has libstdc++ and libgcc_s
#     and not libatomic -- and it reaches this build stage only as a dependency
#     of the `g++` the toolchain step above installs (apt pulls libatomic1 in
#     with it). So the `t3 --version` gate below passes here because the
#     toolchain is present, and an overlay composed onto a template WITHOUT the
#     descriptor's toolchain hook having run cannot start `t3` at all --
#     verified by composing this overlay onto the bare template.
#
#     That makes t3code.yaml's install hook load-bearing for a second reason
#     beyond the one it documents: it is not only what leaves a sandbox able to
#     `npm rebuild` node-pty later, it is what puts libatomic.so.1 on the
#     composed base so the binary this overlay ships can run at all. The hook
#     runs in the install phase, before the agent starts, so `t3` is runnable
#     by the time anything asks for it.
#
# WHAT CHANGES BY COMPILING HERE INSTEAD OF IN THE SANDBOX: node-pty is built
# against this template's Node, and Ubuntu's node-gyp links the addon against
# the distro's shared libnode (libnode.so.127 here), where the hook compiled
# against whatever the sandbox's own base shipped and so always matched. The
# addon is Node-API (`napi_register_module_v1`), so it is not bound to a Node
# ABI version -- the coupling is that one shared library. It does not reach
# the CLI's normal path: composed onto ubuntu:24.04 + nodejs + libatomic1, whose
# Node is 18 with libnode.so.109 rather than the 22 and libnode.so.127 this
# built against, `t3 --version` reports the pinned release, because the launcher
# spawns the standalone platform executable and that links no libnode at all.
#
# The toolchain hook staying in the descriptor is what leaves a sandbox able
# to `npm rebuild` if a base ever does mismatch.

# The overlay: the install prefix and its shim, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays, and T3 Code's SSH
# bootstrap (or a user at the shell) runs `t3`.
FROM scratch
COPY --from=build /out /
