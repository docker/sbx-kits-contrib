# syntax=docker/dockerfile:1
# The content of the `amp` workload kit. The v2 kit shipped no Dockerfile: it
# pointed sandbox.image straight at a published template and installed Amp
# with a create-time hook. A v3 workload's layers are its root filesystem, so
# it must have content -- this recipe states that same template as its base
# and bakes in the install v2 could only do at create time.
#
# The base is v2's sandbox.image carried over verbatim, the `-docker` variant
# included: swapping it for a different template would change what the sandbox
# ships underneath the agent.
FROM docker/sandbox-templates:shell-docker

# The platform floor's user, restated rather than inherited: sbx@1 requires
# the image config to declare a non-empty user for the host to honor, and an
# inherited value is the base's statement rather than this kit's. It is also
# the user the install below has to run as -- v2's hook said `user: "1000"`,
# because install.sh is a per-user installer with no --prefix and lands its
# tree under $HOME.
USER agent

# THE PIN. The kit's `version` arg arrives as this build arg: amp.yaml validates
# its shape and expands the same value into `provides` and into its own
# `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an empty
# fallback is the failure this pin exists to prevent -- install.sh treats an
# unset AMP_VERSION as "install whatever the pointer says", so the install would
# float while the descriptor went on asserting a number. A missing value fails
# the build instead; see the guard in the RUN below.
ARG AMP_VERSION

# THE INSTALL, MOVED OUT OF THE LIFECYCLE HOOK.
#
# v2 had no other option: a v2 mixin could carry no content, so an install
# hook was the only mechanism either form of this kit had. v3 lifts that, and
# the hook was encoding the old limitation rather than a requirement of Amp's
# -- install.sh reads nothing that exists only at sandbox-create time. Baking
# it buys: no download on every sandbox create, `ampcode.com` and its wildcard
# out of the install phase of the kit's permission surface (the descriptor now
# declares no install phase at all), content that is pinned by digest in the
# kit image and scannable there, and an upstream installer that breaks at
# publish rather than in a user's sandbox.
#
# The command is v2's hook body plus the pin. Two details it leans on:
#
#   - HOME is exported rather than inherited. install.sh is $HOME-scoped
#     (AMP_HOME defaults to $HOME/.amp) and this base's image config declares
#     no HOME, so a RUN's value would depend on the builder's passwd lookup
#     rather than on anything this kit states. /home/agent is the sandbox
#     runtime's own home, so the tree the installer writes is the tree the
#     agent finds at run time.
#   - The PATH symlink is what puts `amp` where the entrypoint below can find
#     it. install.sh symlinks its binary into the first of ~/.local/bin,
#     ~/bin, ~/.bin that is already on PATH; the base puts
#     /home/agent/.local/bin first on PATH, so that is where it lands. (Off
#     such a base it would instead append a PATH line to ~/.bashrc, which an
#     exec'd container process never reads -- hence the gate below.)
#
# HOW THE PIN REACHES THE INSTALLER: through the environment. install.sh opens
# with `AMP_VERSION="${AMP_VERSION:-}"` and, when that is non-empty, takes it as
# the version outright -- `version="$AMP_VERSION"` -- and builds the binary and
# checksum URLs from it instead of fetching its version pointer. A build arg is
# already in this RUN's environment, so install.sh inherits it as a child
# process; the `export` says so out loud rather than leaving it to be inferred.
# A value naming no published release fails the download.
#
# `test -x` on both the installed binary and the symlink is the first build-time
# gate: it pins the two assumptions above, so a change of prefix or of symlink
# policy upstream fails the build here instead of shipping an image whose
# entrypoint is not on PATH.
#
# The version comparison is the second, and it is the one the provide rests on:
# the descriptor publishes `amp@${AMP_VERSION}`, so an install that resolved to
# something else would ship a provide that lies about its own content -- the one
# failure mode worse than floating. install.sh's own checksum step is not a
# substitute. It verifies the download against the SHA256 published *beside the
# version it asked for*, which proves the bytes are that artifact, not that the
# artifact reports the release this kit names. `amp --version` prints
# `<version> (released <date>, <age> ago)`, so the first field is the number to
# match.
#
# This does execute a ~100 MB self-contained binary, which on a
# `--platform linux/amd64,linux/arm64` build means running the foreign leg under
# emulation -- the cost an earlier note here declined to pay when there was no
# pin to verify. It is a cheap call even so: the string it prints is baked into
# the binary (the "released ... ago" part is arithmetic on the timestamp inside
# its own version), so it reaches no network and returns in under a second
# natively.
RUN set -eux; \
    export HOME=/home/agent; \
    [ -n "$AMP_VERSION" ] || { echo "AMP_VERSION must be set" >&2; exit 1; }; \
    export AMP_VERSION; \
    curl -fsSL https://ampcode.com/install.sh | bash; \
    test -x "$HOME/.amp/bin/amp"; \
    test -x "$HOME/.local/bin/amp"; \
    reported="$("$HOME/.amp/bin/amp" --version)"; \
    echo "amp --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $1}')"; \
    [ "$installed" = "$AMP_VERSION" ] || { \
      echo "pin mismatch: descriptor says $AMP_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

# Where the host places the workspace under sbx@1. v2 had no Dockerfile and so
# no working directory of its own; this is the conventional sibling of $HOME
# that leaves the agent's home free for the tooling Amp installs into it.
WORKDIR /home/agent/workspace

# v2's sandbox.entrypoint. The binary it names is now in this image's layers
# rather than installed into the container before the entrypoint first runs;
# either way it is on PATH by the time the host launches it.
#
# v2 declared no environment.variables, so this image sets no ENV.
ENTRYPOINT ["amp", "--dangerously-allow-all"]
