# syntax=docker/dockerfile:1
# Overlay recipe for the kiro mixin.
#
# cli.kiro.dev's install script is an opaque `curl | bash` with a user-scoped
# prefix: it lays kiro-cli under $HOME/.local and `kiro-cli setup` seeds state
# beside it at absolute paths. There is no --prefix to redirect it at, so this
# takes the shape the guide prescribes for an unrelocatable install — the
# workload's own base as a build stage, the unmodified install run on it, and
# the specific resulting paths copied into a scratch overlay.
#
# No version build arg, unlike the sibling agent mixins in this repo. The
# installer takes none: its whole option surface is `--help` and
# `--channel CHANNEL`, it refuses anything else (`*) error "Unknown option:
# $1"`), it reads no version from the environment, and the URLs it builds
# spell the release as the literal `latest`
# (`${BASE_URL}/${CHANNEL}/latest/manifest.json`). So the descriptor declares
# no `args` and publishes an unversioned provide — see the note beside
# `provides:` in kiro-mixin.yaml for the full evidence.
#
# It runs as `agent` with HOME at /home/agent, the sandbox runtime's own home,
# so the paths the installer and `setup` bake are already correct when the
# overlay lands.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The launcher the user resolves as `kiro`: it checks authentication state and
# drops into the device flow before handing off to kiro-cli. It is what makes
# this kit "Kiro with interactive device-flow authentication" rather than just
# kiro-cli, so the mixin carries it even though it has no entrypoint to invoke
# it from — the user runs `kiro` and gets the same behavior.
#
# MIGRATION NOTE: this file is a copy of ../kiro/start.sh, not a reference to
# it. A kit's build context is rooted at its own descriptor's directory and
# may not escape it (SPEC-v3 §4), so a sibling kit's assets are unreachable
# from here. The two must move together — see this kit's README.
COPY --chown=agent:agent --chmod=0755 start.sh /home/agent/.local/bin/kiro

USER agent
ENV HOME=/home/agent
WORKDIR /home/agent
RUN <<EOF
set -ex
curl -fsSL https://cli.kiro.dev/install | bash

# Runs kiro-cli setup to have it create ~/.local/share/kiro-cli/data.sqlite3.
# The descriptor re-runs this as an install hook at sandbox create, because a
# volume mounted over ~/.local/share/kiro-cli would shadow this copy.
kiro-cli setup --no-confirm
EOF

USER root
# v2's environment.variables. A mixin's image config is not the composed
# image's, so ENV would be dropped at assembly — the export rides the overlay
# instead, sourced by the base workload's login shell.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/kiro-env.sh <<'EOF'
export IS_SANDBOX=1
EOF

# The specific resulting paths: kiro-cli, the launcher and the state `setup`
# seeded, all under the agent's home. `test -x` pins the assumption that the
# installer lands under ~/.local/bin, so a change of prefix upstream fails the
# build here rather than shipping an overlay with no agent in it.
RUN set -eux; \
    mkdir -p /out/home/agent /out/usr/local/bin; \
    cp -a /home/agent/.local /out/home/agent/.local; \
    chown -R 1000:1000 /out/home/agent; \
    test -x /out/home/agent/.local/bin/kiro-cli; \
    test -x /out/home/agent/.local/bin/kiro; \
    ln -s /home/agent/.local/bin/kiro /out/usr/local/bin/kiro; \
    ln -s /home/agent/.local/bin/kiro-cli /out/usr/local/bin/kiro-cli

# The bin shims above, not a profile.d PATH export: ~/.local/bin is on PATH on
# the shell templates but a mixin lands on any base, and /usr/local/bin is on
# every one of them. `kiro-cli` gets one as well as `kiro`, because the
# descriptor's install hook invokes it by bare name.

# The overlay: kiro-cli, its device-flow launcher and its seeded state,
# landing on any base. No ENTRYPOINT — the base workload's launch command
# stays, and the user runs `kiro` from the shell. v2's `chat
# --trust-all-tools` were entrypoint flags and belong to the workload.
FROM scratch
COPY --from=build /out /
