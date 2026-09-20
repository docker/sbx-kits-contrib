# syntax=docker/dockerfile:1
# An overlay, not a root filesystem. Neovim itself still comes from the install
# hook — the download needs the sandbox's network policy, which a build does not
# have — so this recipe carries only what the v2 kit shipped as static content.
#
# The assembly stage is here to own the result precisely: BuildKit applies a
# COPY --chown to every parent directory it creates, so copying straight into a
# scratch stage would hand /home itself to the agent. Staging under /out and
# chowning only the agent's own subtree leaves /home as the base has it, which
# is what v2's create-time copy into an existing tree did.
FROM busybox:1.37 AS build

# v2's `files/home/` tree, landing where the v2 convention put it:
# /home/agent/<relative path>. Chowned by number — busybox has no `agent` user,
# and uid/gid 1000 is the platform floor's agent.
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# MIGRATION NOTE: v2's `environment.variables` land here. A mixin has no
# `environment:` slot in v3 and its image config is not the composed image's,
# so the variables ride the overlay as a profile.d snippet the base's login
# shell sources.
RUN mkdir -p /out/etc/profile.d && cat > /out/etc/profile.d/neovim-env.sh <<'EOF'
export EDITOR=nvim
export VISUAL=nvim
EOF

# The overlay: the bundled nvim config and the kit's exports, on any base.
FROM scratch
COPY --from=build /out /
