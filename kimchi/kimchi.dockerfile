# syntax=docker/dockerfile:1
# Content for the `kimchi` workload kit.
#
# MIGRATION NOTE: this was v2's Dockerfile, built by CI into
# docker.io/sbx/kimchi-image:latest and named back from spec.yaml's
# `sandbox.image`. In v3 the recipe is the kit's content directly, so the
# published-tag round trip is gone. The base is v2's default, carried over
# verbatim.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

# Re-declared inside the stage: an ARG defined before the first FROM is a
# global build arg, visible only to FROM lines. Without this, the LABEL below
# would expand to an empty string.
ARG BASE_IMAGE

# The platform floor's user, restated rather than inherited: sbx@1 requires
# the image config to declare a non-empty user for the host to honor, and an
# inherited value is the base's statement rather than this kit's. It is also
# the user the install below has to run as -- the installer is per-user, with
# no --prefix, and lands its tree under $HOME.
USER agent

# THE PIN. The kit's `version` arg arrives as this build arg: kimchi.yaml
# validates its shape and expands the same value into `provides` and into its
# own `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an
# empty fallback is the failure this pin exists to prevent -- install.sh
# treats an unset KIMCHI_VERSION as "install whatever latest says", so the
# install would float while the descriptor went on asserting a number. A
# missing value fails the build instead; see the guard in the RUN below.
ARG KIMCHI_VERSION

# THE INSTALL, MOVED OUT OF THE LIFECYCLE HOOK.
#
# v2 had no other option: a v2 kit could carry no content of its own -- the
# image was a published template and the install was a create-time hook.
# v3 lifts that, and the hook was encoding the old limitation rather than a
# requirement of Kimchi's: install.sh reads nothing that exists only at
# sandbox-create time (no kit arg, no workspace path, no credential). Baking
# it buys: no download on every sandbox create, the GitHub release hosts out
# of the install phase of the kit's permission surface, content that is
# pinned by digest in the kit image and scannable there, and an upstream
# installer that breaks at publish rather than in a user's sandbox.
#
# The command is v2's hook body plus the pin. Two details it leans on:
#
#   - HOME is exported rather than inherited. The installer is $HOME-scoped
#     (it falls back to $HOME/.local/bin when /usr/local/bin is not writable,
#     which it is not for the agent user) and this base's image config
#     declares no HOME, so a RUN's value would depend on the builder's
#     passwd lookup rather than on anything this kit states. /home/agent is
#     the sandbox runtime's own home, so the tree the installer writes is the
#     tree the agent finds at run time.
#   - KIMCHI_VERSION is the installer's own pin variable. install.sh opens
#     with `VERSION="${KIMCHI_VERSION:-latest}"` and, when that is non-empty,
#     takes it as the version outright and builds the tarball URL from it
#     instead of resolving the "Latest release" pointer. A build arg is
#     already in this RUN's environment and install.sh inherits it as a child
#     process; the `export` says so out loud rather than leaving it to be
#     inferred.
#
# HOW THE PIN REACHES THE INSTALLER: through the environment. A value naming
# no published release fails the download.
#
# THE `v` TRANSLATION, and why it lives here. The descriptor's version is
# bare -- "1.39.2" -- because that is what `provides` needs: a version is
# `[0-9]+(\.[0-9A-Za-z-]+)*` with no prefix (SPEC-v3 §5.2), and a "v" in a
# provide would not compare equal to the same point spelled another way. The
# RELEASE TAG is "v1.39.2", and install.sh builds its download URL by
# interpolating KIMCHI_VERSION verbatim:
#
#     https://github.com/$REPO/releases/download/$VERSION/kimchi_$OS_$ARCH.tar.gz
#
# so it needs the tag's spelling. The two differ by exactly this prefix, and
# the conversion is the recipe's business because the recipe is what talks to
# the installer. Doing it here rather than in the descriptor keeps one rule in
# one place: the descriptor states versions the way the specification spells
# them, and the recipe states the one way this upstream installer wants them.
#
# The two `test -x` gates are the first build-time checks: they pin the
# assumption that the binary and the share tree stay under one prefix, so a
# change of prefix policy upstream fails the build here instead of shipping an
# image whose entrypoint is not on PATH.
#
# WHY THE SHARE TREE MATTERS, and why the version is read from it rather than
# from the binary's own output: the CLI resolves its auxiliary files
# (themes, skills, the OAuth pages, the bridge installer) by looking for a
# `share/kimchi` directory beside the executable -- `join(execPath, "..",
# "..", "share", "kimchi")` -- and only falls back to $XDG_DATA_HOME or
# ~/.local/share/kimchi when that path has no package.json in it. The
# installer keeps the two under one prefix for exactly that reason, so the
# binary finds its share tree and reports the version from its package.json.
#
# The version comparison is the second check, and it is the one the provide
# rests on: the descriptor publishes `kimchi@${KIMCHI_VERSION}`, so an install
# that resolved to something else would ship a provide that lies about its
# own content -- the one failure mode worse than floating. `kimchi --version`
# prints the version and nothing else, so the first field is the number to
# match.
#
# This executes a ~160 MB self-contained binary, which on a
# `--platform linux/amd64,linux/arm64` build means running the foreign leg
# under emulation. It is a cheap call even so: the version it prints is
# baked into the binary and read out of the share tree, so it reaches no
# network and returns in under a second natively.
RUN set -eux; \
    export HOME=/home/agent; \
    [ -n "$KIMCHI_VERSION" ] || { echo "KIMCHI_VERSION must be set" >&2; exit 1; }; \
    pin="$KIMCHI_VERSION"; \
    export KIMCHI_VERSION="v${pin}"; \
    curl -fsSL https://github.com/getkimchi/kimchi/releases/latest/download/install.sh | bash; \
    test -x "$HOME/.local/bin/kimchi"; \
    test -f "$HOME/.local/share/kimchi/package.json"; \
    reported="$("$HOME/.local/bin/kimchi" --version)"; \
    echo "kimchi --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $1}')"; \
    [ "$installed" = "$pin" ] || { \
      echo "pin mismatch: descriptor says $pin, binary reports '$reported'" >&2; \
      exit 1; \
    }

# Where the host places the workspace under sbx@1. The base's own working
# directory is already /home/agent/workspace, and restating it is what this
# repo's other workloads do; it is stated here rather than inherited so the
# kit's paths and the host's agree (sbx@1 places the workspace at the image
# config's working directory).
WORKDIR /home/agent/workspace

# Overrides the base's flavor: sbx reads it as the image's agent.
LABEL com.docker.sandboxes.flavor="kimchi"

# Informational; nothing in sbx reads it. Records what this image was built
# on, since the base is a floating tag rebuilt nightly.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

# v2's sandbox.entrypoint. The binary it names is now in this image's layers
# rather than installed into the container before the entrypoint first runs;
# either way it is on PATH by the time the host launches it.
#
# MIGRATION NOTE: v2's Dockerfile ended with `CMD ["kimchi"]`, which mirrored
# its entrypoint. Beside a migrated ENTRYPOINT that CMD becomes a stray
# trailing argument -- the effective launch argv would be `kimchi kimchi` --
# so it is dropped. SPEC-v3 §8 maps `sandbox.command.default` onto CMD, and
# v2 declared no `sandbox.command` at all, so there is no default argument to
# carry over. The headless invocation's own arguments come from
# agent-sessions@1, which appends a tail to this entrypoint.
ENTRYPOINT ["kimchi"]
