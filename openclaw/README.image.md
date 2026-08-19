# sbx/openclaw-image

Base image for the OpenClaw agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`. On top of that:

- Node 22 (OpenClaw requires >= 22.19)
- `openclaw`, installed globally at a pinned version
- Chromium + headless deps for OpenClaw's browser tool, under
  `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`
- `/usr/local/bin/openclaw-start`, the entrypoint that ensures
  `gateway.mode=local`, starts the gateway in the background, and drops
  into `openclaw chat`

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/openclaw-start"]`.

## Kit

[`docker.io/sbx/openclaw-kit`](https://hub.docker.com/r/sbx/openclaw-kit)
