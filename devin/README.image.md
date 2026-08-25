# sbx/devin-image

Base image for the Devin agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- [Devin CLI](https://docs.devin.ai/cli) ("Devin for Terminal"), installed from
  `cli.devin.ai` into the `agent` user's `~/.local` tree
- `/home/agent/.local/bin/devin-cli` — the CLI itself, tracking the installer's
  `_versions/current` symlink
- `/home/agent/.local/bin/devin` — a wrapper that checks `devin-cli auth status`
  and falls back to `devin-cli auth login --force-manual-token-flow`, then execs
  `devin-cli`

Runs as the non-root `agent` user, with `CMD ["devin"]`.

## Kit

[`docker.io/sbx/devin-kit`](https://hub.docker.com/r/sbx/devin-kit)
