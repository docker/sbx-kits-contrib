# sbx/kiro-image

Base image for the Kiro agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `kiro-cli`, installed from its `latest` channel
- `/home/agent/.local/bin/kiro` — a wrapper that runs `kiro-cli whoami` and
  falls back to `kiro-cli login --use-device-flow`, then execs `kiro-cli`
- `~/.local/share/kiro-cli/data.sqlite3`, created by `kiro-cli setup` so it can
  be placed on a volume

Runs as the non-root `agent` user, with `CMD ["kiro"]`.

## Kit

[`docker.io/sbx/kiro-kit`](https://hub.docker.com/r/sbx/kiro-kit)
