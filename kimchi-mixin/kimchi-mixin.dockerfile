# syntax=docker/dockerfile:1
# Kimchi as an overlay.
#
# The workload (../kimchi) installs Kimchi into the agent's own home, because
# it owns its root filesystem and the faithful thing there is the install v2's
# hook performed, under $HOME. An overlay lands on a base this repo does not
# control, so the install has to move somewhere the base cannot take away --
# and /opt is the answer, because /home/agent on a composed base may be a
# mounted volume that would cover the overlay's content at create.
#
# THE RELOCATION IS NOT A RELOCATION PROBLEM, because the installer was
# written for it. install.sh takes the prefix from two variables:
#
#     KIMCHI_INSTALL_DIR  where the binary goes   -> <prefix>/bin/kimchi
#     XDG_DATA_HOME       where the share tree goes -> <prefix>/share/kimchi
#
# and the two are what makes the binary find its own auxiliary files. The CLI
# resolves them in this order:
#
#     <execPath>/../../share/kimchi     (relative to the binary)
#     $XDG_DATA_HOME/kimchi
#     $HOME/.local/share/kimchi
#
# so a binary at <prefix>/bin/kimchi finds <prefix>/share/kimchi by the FIRST
# rule, with no environment variable set at all. That is what makes this
# overlay self-contained: it ships both halves under one prefix, and the
# binary locates its share tree relative to itself rather than relative to a
# HOME the composed base happens to have.
#
# The install runs as the base image's default user (agent, uid 1000), because
# the installer writes into the prefix this stage creates and /opt must be
# root's in the final overlay anyway -- so the stage installs as root and the
# staged tree is chowned below.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN. The kit's `version` arg arrives as this build arg:
# kimchi-mixin.yaml validates its shape and expands the same value into
# `provides` and into its own `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an
# empty fallback is the failure this pin exists to prevent -- install.sh treats
# an unset KIMCHI_VERSION as "install whatever latest says", so the install
# would float while the descriptor went on asserting a number. A missing value
# fails the build instead; see the guard in the RUN below.
ARG KIMCHI_VERSION

USER root

# THE INSTALL, at build time.
#
# The `v` PREFIX: the descriptor's version is bare -- "1.39.2" -- because that
# is what `provides` needs (SPEC-v3 §5.2: a version carries no prefix), while
# the RELEASE TAG is "v1.39.2" and install.sh builds its download URL by
# interpolating KIMCHI_VERSION verbatim. The two differ by exactly this
# prefix, and the conversion is the recipe's business because the recipe is
# what talks to the installer.
#
# The three checks after the install:
#
#   - `test -x` on the binary and on the share tree's package.json: they pin
#     the assumption that both halves stayed under one prefix, so a change of
#     prefix policy upstream fails the build here rather than shipping an
#     overlay whose CLI cannot find its own resources.
#   - the version comparison: the descriptor publishes
#     `kimchi@${KIMCHI_VERSION}`, so an install that resolved to something
#     else would ship an overlay whose provide lies about its own content --
#     the one failure mode worse than floating. `kimchi --version` prints the
#     version and nothing else, so the first field is the number to match.
#
# The version check is run with XDG_DATA_HOME UNSET on purpose: that is the
# state the composed sandbox is in, and it proves the binary finds its share
# tree by the FIRST resolution rule -- relative to its own path -- rather than
# by leaning on an environment variable the overlay does not ship. A build
# that only passed with XDG_DATA_HOME set would ship a broken overlay.
RUN set -eux; \
    [ -n "$KIMCHI_VERSION" ] || { echo "KIMCHI_VERSION must be set" >&2; exit 1; }; \
    pin="$KIMCHI_VERSION"; \
    export KIMCHI_VERSION="v${pin}"; \
    export KIMCHI_INSTALL_DIR=/opt/kimchi/bin; \
    export XDG_DATA_HOME=/opt/kimchi/share; \
    curl -fsSL https://github.com/getkimchi/kimchi/releases/latest/download/install.sh | bash; \
    test -x /opt/kimchi/bin/kimchi; \
    test -f /opt/kimchi/share/kimchi/package.json; \
    reported="$(env -u XDG_DATA_HOME /opt/kimchi/bin/kimchi --version)"; \
    echo "kimchi --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $1}')"; \
    [ "$installed" = "$pin" ] || { \
      echo "pin mismatch: descriptor says $pin, binary reports '$reported'" >&2; \
      exit 1; \
    }

# The staged tree: the install prefix and one shim, nothing under /home.
#
# The shim is a symlink in /usr/local/bin rather than a PATH export in
# /etc/profile.d: /usr/local/bin is on PATH on every base and in every kind
# of shell, while a profile.d file is only read by a login shell -- and `sbx
# exec` and an agent's own subprocesses are not that.
#
# Ownership is explicit rather than inherited from the install: everything
# here is root's, which is what /opt and /usr/local/bin are on any base.
# Numeric because `scratch` carries no /etc/passwd for a name to resolve
# against.
#
# The share tree is copied whole: it carries the themes, the skills, the
# OAuth pages and the bridge installer, and the binary needs all of it.
RUN set -eux; \
    mkdir -p /out/opt /out/usr/local/bin; \
    cp -a /opt/kimchi /out/opt/kimchi; \
    chown -R 0:0 /out/opt /out/usr/local/bin; \
    ln -s /opt/kimchi/bin/kimchi /out/usr/local/bin/kimchi

# The overlay: the install prefix and its shim, landing on any base. No
# ENTRYPOINT -- the base workload's launch command stays, and the user runs
# `kimchi` from the shell.
FROM scratch
COPY --from=build /out /
