# sbx/codex-image

Base image for the Codex agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `@openai/codex`, OpenAI's Codex CLI, installed globally from npm with its
  platform-specific native binary

Runs as the non-root `agent` user, with `CMD ["codex"]`.

## Kit

[`docker.io/sbx/codex-kit`](https://hub.docker.com/r/sbx/codex-kit)
