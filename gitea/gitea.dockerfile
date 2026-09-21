# syntax=docker/dockerfile:1
# Gitea's `tea` CLI as an overlay, plus the kit's one static export.
#
# WHAT MOVED HERE. Until now this file carried only the profile.d export, and
# `tea` arrived from a lifecycle install hook -- the shape a v2 mixin was
# forced into, since a v2 mixin had no content mechanism at all and an install
# hook was the only way for one to install anything. The first v3 cut
# transcribed that faithfully. But this download is pure content: a version-
# and SHA256-pinned release binary that reads nothing existing only at
# sandbox-create time. Building it buys no per-create download, a digest fixed
# in a layer that can be scanned, a bad release failing at publish instead of
# in a user's sandbox, and -- visible in the kit's permission surface --
# dl.gitea.com gone from gitea.yaml, whose network policy now has no install
# phase at all.
#
# WHAT STAYED A HOOK, and why, in gitea.yaml: seeding ~/.config/tea/config.yml.
# It writes the instance hostname out of the kit's create-phase `host` arg and
# the proxy-managed GITEA_TOKEN sentinel, neither of which exists at build --
# the instance is the installer's choice, made once per sandbox. That is the
# definition of create-time work, and no layer can hold it.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# THE PIN, handed in by the frontend from the descriptor's `version` arg
# (buildArg: TEA_VERSION), which gitea.yaml also expands into `provides` and
# into its own `version:` -- so the release is stated in exactly one place.
#
# No default, deliberately: the descriptor always supplies one, and a silent
# empty fallback would build a nonsense URL. The guard below fails instead.
#
# The per-arch SHA256s stay here beside it, carried over from the install hook
# unchanged. They are what makes an installer-supplied `version` safe: a
# different release fails the digest check rather than installing quietly
# under a descriptor still publishing this number. Bumping tea is the
# three-part edit the README documents -- the arg's default in gitea.yaml and
# both digests here, together -- sourced from
# https://dl.gitea.com/tea/<version>/tea-<version>-linux-<arch>.sha256
ARG TEA_VERSION
ARG TARGETARCH

USER root

# TARGETARCH rather than the hook's `dpkg --print-architecture`: this runs at
# build, where buildx sets it per platform, so `--platform linux/amd64,
# linux/arm64` resolves each leg to its own asset. The hook could only ever see
# the one sandbox it ran in -- which is also why gitea.yaml no longer requires
# `deb/dpkg`: nothing left in the sandbox asks dpkg anything.
#
# The asset is a bare binary rather than an archive, so there is no tarball to
# unpack and no publisher uid riding in with it; `install -o 0 -g 0` states the
# ownership anyway, because `scratch` has no /etc/passwd to resolve a name
# against and an overlay's entries override the base's.
RUN set -eu; \
    [ -n "${TEA_VERSION}" ] || { echo "TEA_VERSION must be set" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) \
        sha256=aac99cc6e650a81ae7b5061f8c75bc0eade4509c828d97b6072e1f0a3bd24357 ;; \
      arm64) \
        sha256=0db109df6696bfe01f9203402f503404692404d4ea9c16a540ecaeecc8e6bab2 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH} (expected amd64 or arm64)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/tea \
      "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-${TARGETARCH}"; \
    echo "${sha256}  /tmp/tea" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    install -m 0755 -o 0 -g 0 /tmp/tea /out/usr/local/bin/tea; \
    rm -f /tmp/tea

# THE GATE. The hook ended with a bare `tea --version`, which proved the binary
# starts; this compares what it prints against the pin as well, because the
# descriptor now publishes `tea@<the version arg>` and an overlay whose content
# disagreed with its own provide is the one failure worse than floating.
#
# It splits the reported line into fields and demands one equal to the pin,
# rather than testing for a substring: `0.15.1` is a substring of `10.15.11`,
# and tea's label wording is not this kit's to depend on.
#
# The ANSI strip is not defensive dressing. tea prints its version wrapped in a
# bold SGR pair -- `Version: \033[1m0.15.1\033[0m` -- and does so with stdout
# redirected to a pipe in a build, where a tool that consults isatty would not.
# Without the strip the field is the escape sequence rather than the number and
# the comparison fails against a correct binary; a substring test would instead
# have passed and hidden the whole thing. ESC comes from printf because a
# literal one has no business in a source file.
#
# The emptiness guard is repeated here rather than left to the download step.
# `grep -Fxq ""` matches every line, so an unset pin would turn this gate into
# an unconditional pass -- the one way a verification step is worse than none.
#
# The output is captured whole and trimmed afterwards rather than piped into
# `head`, so that `set -e` sees the tool's own exit status rather than head's
# -- a binary that prints its version and then fails should not pass a gate
# whose job is to prove the content works. It also avoids killing a chatty
# tool with SIGPIPE, which is what the sibling mise recipe hit.
RUN <<'EOF'
set -eu
[ -n "${TEA_VERSION}" ] || { echo "TEA_VERSION must be set" >&2; exit 1; }
esc=$(printf '\033')
out="$(/out/usr/local/bin/tea --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
plain="$(printf '%s\n' "$reported" | sed "s/${esc}\[[0-9;]*[A-Za-z]//g")"
echo "tea --version: ${plain}"
printf '%s\n' "$plain" | tr -s ' ,:\t' '\n' | grep -Fxq "${TEA_VERSION}" || {
  echo "pin mismatch: descriptor says ${TEA_VERSION}, binary reports '${plain}'" >&2
  exit 1
}
EOF

# The kit's one static export, unchanged in content and in reasoning.
#
# v3 has no static env grammar -- the image config owns runtime env, and a
# mixin's image config is not the composed image's (SPEC-v3 §10), so the v2
# `environment.variables` block has nowhere to land as a field. The export
# rides the overlay instead, in a file the base workload's login shell sources.
#
# The variable itself is carried over verbatim from v2: never block on a git
# credential prompt in a non-interactive session. The proxy injects the
# Authorization header before the request leaves the sandbox, so git never sees
# a 401 and never needs a credential helper -- but if the host is ever
# misconfigured, failing beats hanging.
RUN set -eu; \
    mkdir -p /out/etc/profile.d; \
    printf 'export GIT_TERMINAL_PROMPT=0\n' > /out/etc/profile.d/gitea-env.sh; \
    chmod 0644 /out/etc/profile.d/gitea-env.sh; \
    chown -R 0:0 /out/etc

# The overlay: one pinned binary and one profile.d snippet, landing on any
# base. Nothing under /home -- /usr/local and /etc/profile.d are what a mixin
# landing on an unknown base should prefer, since whatever is at /home/agent
# may be a mounted volume, and the one thing this kit does write there stays a
# hook for exactly that reason. No ENTRYPOINT -- the base workload's launch
# command stays, and the agent runs `tea` from the shell.
FROM scratch
COPY --from=build /out /
