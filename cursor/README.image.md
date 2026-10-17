# sbx/cursor-image

Base image for the Cursor agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `cursor-agent`, Cursor's CLI coding agent, installed via the upstream install
  script into `/home/agent/.local/bin/cursor-agent`

Runs as the non-root `agent` user, with
`CMD ["/home/agent/.local/bin/cursor-agent"]`.

## Kit

[`docker.io/sbx/cursor-kit`](https://hub.docker.com/r/sbx/cursor-kit)
