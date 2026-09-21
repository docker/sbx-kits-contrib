# syntax=docker/dockerfile:1
# Content recipe for the `grok` kit.
#
# The v2 kit shipped no Dockerfile: it pointed `sandbox.image` straight at
# this published template and let a setup hook install the agent at
# sandbox-create time. A v3 workload MUST have content — its layers are the
# root filesystem — so this recipe states that template as its base and bakes
# the install into it.
#
# The image reference is v2's `sandbox.image` carried over verbatim, not
# re-pointed at another registry: the template is what the kit was built and
# tested against, and it carries the platform floor (bash, the agent user,
# git, a CA store) a workload is expected to stand on.
FROM docker/sandbox-templates:shell-docker

# The platform floor's user, restated rather than inherited: the install below
# has to run as the agent (v2's hook said `user: "1000"`), and sbx@1 wants the
# image config to declare a non-empty user of this kit's own rather than
# leaving the base's statement to stand. It is also the last USER in the file
# on purpose — the published identity is `agent`, as it was in v2.
USER agent

# THE PIN. The kit's `version` arg arrives as this build arg: grok.yaml
# validates its shape and expands the same value into `provides` and into its
# own `version:` field.
#
# No default here, deliberately. The descriptor always supplies one, and an
# empty fallback is the failure this pin exists to prevent — the install would
# float to whatever the installer's channel pointer currently resolves while the
# descriptor went on asserting a number. A missing value fails the build
# instead; see the guard in the RUN below.
ARG GROK_VERSION

# THE INSTALL, MOVED OUT OF THE LIFECYCLE HOOK.
#
# Through v2 and the first v3 cut this was a `lifecycle@1` install hook,
# because a v2 mixin had no way to carry content and the workload matched its
# sibling. v3 lifts that, and ../grok-mixin already bakes the same install
# into its overlay; this is the workload catching up. What the move buys: no
# per-sandbox-create download, `x.ai` out of the kit's permission surface
# entirely (the descriptor now declares no install phase at all), content that
# is digest-pinned in the kit image and scannable, and an upstream installer
# breaking at publish instead of in a user's sandbox.
#
# The command is v2's hook body plus the pin. Two details it depends on:
#
#   - HOME is exported rather than inherited. The installer is $HOME-scoped
#     and the base's image config declares no HOME, so a RUN's value would
#     depend on the builder's passwd lookup rather than on anything this kit
#     states. /home/agent is the sandbox runtime's own home, so the paths the
#     installer bakes are the paths the agent finds at run time.
#   - The mkdir is load-bearing. The installer only symlinks `grok` onto an
#     existing, writable PATH directory (~/.local/bin or /usr/local/bin); it
#     does not create either. ~/.local/bin is on the base's PATH already but
#     the image never creates it, so without this the installer would silently
#     fall through to rewriting .bashrc/.zshrc instead — which the
#     non-interactive kit entrypoint never sources.
#
# HOW THE PIN REACHES THE INSTALLER: as install.sh's first positional argument,
# which `bash -s` is what forwards to a script read from a pipe. That is the
# installer's own documented interface for it (`... | bash -s 0.1.42`), and it
# validates the target itself, refusing anything that is not X.Y.Z[-suffix].
# With it set, the installer skips its channel-pointer fetch and builds the
# artifact URL from this version directly, so a value naming no published
# release fails the download rather than falling back to the newest.
#
# `test -x` is the first build-time gate, the same one ../grok-mixin uses: it
# pins the assumption that the installer lands a symlink under ~/.local/bin, so
# a change of prefix upstream fails the build here rather than shipping an image
# with no agent in it.
#
# The version comparison is the second, and it is what makes the provide
# trustworthy rather than merely requested: the descriptor publishes
# `grok@${GROK_VERSION}`, so an install that resolved to something else would
# ship a provide that lies about its own content — the one failure mode worse
# than floating. `grok --version` prints `grok <version> (<commit>)`, so the
# second field is the number to match.
#
# Running the binary is not a new class of build-time behavior: install.sh
# already executes the freshly downloaded artifact itself, once as
# `<binary> --version` to verify it starts at all and again to generate shell
# completions, and fails the install if the first of those does not run. The
# earlier note here — that this step avoided `grok --version` because it would
# reach the network — was wrong on both counts.
RUN set -eux; \
    export HOME=/home/agent; \
    [ -n "$GROK_VERSION" ] || { echo "GROK_VERSION must be set" >&2; exit 1; }; \
    mkdir -p "$HOME/.local/bin"; \
    curl -fsSL https://x.ai/cli/install.sh | bash -s "$GROK_VERSION"; \
    test -x "$HOME/.local/bin/grok"; \
    reported="$("$HOME/.local/bin/grok" --version)"; \
    echo "grok --version: $reported"; \
    installed="$(printf '%s\n' "$reported" | awk 'NR==1{print $2}')"; \
    [ "$installed" = "$GROK_VERSION" ] || { \
      echo "pin mismatch: descriptor says $GROK_VERSION, binary reports '$reported'" >&2; \
      exit 1; \
    }

# v2's `sandbox.entrypoint`, in the slot OCI already owns for launch config —
# the v3 descriptor carries none. `--yolo` auto-approves tool calls (the
# sandbox itself is the safety boundary) and `--no-auto-update` disables the
# background update check, since the sandbox is recreated from the kit rather
# than self-updated in place — which is also why nothing reaches `x.ai` once
# the image is built.
ENTRYPOINT ["grok", "--yolo", "--no-auto-update"]
