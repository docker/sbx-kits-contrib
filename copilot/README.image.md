# sbx/copilot-image

Base image for the GitHub Copilot agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `copilot`, GitHub's Copilot CLI, installed via the upstream install script

Runs as the non-root `agent` user, with `CMD ["copilot"]`.

## Kit

[`docker.io/sbx/copilot-kit`](https://hub.docker.com/r/sbx/copilot-kit)
