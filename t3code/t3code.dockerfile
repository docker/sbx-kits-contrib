# syntax=docker/dockerfile:1
# T3 Code's `t3` CLI as an overlay.
#
# `t3` is pure content: `npm install -g` reads nothing that exists only at
# sandbox-create time, so it is built once here instead of once per sandbox,
# and registry.npmjs.org leaves the kit's permission surface. The package's
# platform dependency ships prebuilt native modules (node-pty among them), so
# no compiler is involved. The one thing the binaries need that the templates
# lack is libatomic1, and apt cannot travel in an overlay: the descriptor's
# install hook adds it in the sandbox, and this stage adds it only so the
# `t3 --version` gate below can run.
#
# The base is the image family the kit documents as its target -- Node >= 18
# with npm, which every standard agent template ships.
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

# Only so the gate below can start the binary; it never reaches the overlay.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends libatomic1; \
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
#     installed the launcher and nothing to launch, and T3 Code then reports
#     nothing more specific than a connection timeout. At build it is a red
#     build instead of a broken sandbox.
#   - The prebuilt node-pty check pins the reason no compiler is installed:
#     a release whose node-pty had to compile would otherwise be dropped by
#     npm as a failed optional dependency and still exit 0.
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
    find /opt/t3 -path '*/node-pty/prebuilds/linux-*/pty.node' | grep -q . || { \
      echo "node-pty did not arrive prebuilt; this release would need a compiler" >&2; \
      exit 1; \
    }; \
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

# WHAT THIS OVERLAY CANNOT CARRY, both verified by composing it onto bases
# that are not this one:
#
#   - A Node runtime. The package's bin entry is `#!/usr/bin/env node`, so the
#     composed base must have node on PATH.
#   - libatomic1. The platform binary links it, no sandbox template ships it
#     (checked with ldconfig on docker/sandbox-templates:shell-docker), and
#     an overlay cannot carry dpkg state. t3code.yaml's install hook adds it
#     before the agent starts, so `t3` is runnable by the time anything asks.
# The overlay: the install prefix and its shim, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays, and T3 Code's SSH
# bootstrap (or a user at the shell) runs `t3`.
FROM scratch
COPY --from=build /out /
