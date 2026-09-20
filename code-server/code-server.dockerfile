# syntax=docker/dockerfile:1
# An overlay, not a root filesystem. code-server itself still comes from the
# install hook — the upstream install script needs the sandbox's network policy,
# which a build does not have — so this recipe carries only the VS Code user
# settings the v2 kit shipped under `files/`.
#
# The assembly stage is here to own the result precisely: BuildKit applies a
# COPY --chown to every parent directory it creates, so copying straight into a
# scratch stage would hand /home itself to the agent. Staging under /out and
# chowning only the agent's own subtree leaves /home as the base has it, which
# is what v2's create-time copy into an existing tree did.
FROM busybox:1.37 AS build

# v2's `files/home/` tree, landing where the v2 convention put it:
# /home/agent/<relative path>, so settings.json stays at
# /home/agent/.local/share/code-server/User/settings.json. The agent must own
# it — code-server rewrites this file when a setting is changed in the UI — and
# it is chowned by number because busybox has no `agent` user.
COPY files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

# The overlay: the VS Code user settings, on any base.
FROM scratch
COPY --from=build /out /
