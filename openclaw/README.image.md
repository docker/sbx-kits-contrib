# sbx/openclaw-image

Base image for the OpenClaw agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`. On top of that:

- Node 24 (OpenClaw 2026.9.3 requires >= 24.16.0 < 25, or >= 26.1.0)
- `openclaw`, installed globally at a pinned version
- Chromium + headless deps for OpenClaw's browser tool, under
  `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`
- `/usr/local/bin/openclaw-start`, the entrypoint that waits for the gateway
  the kit's startup command brings up, then drops into `openclaw tui`
  (connected to that gateway; `openclaw chat` would ask for the in-process
  runtime, which openclaw refuses while a gateway holds the state directory)

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/openclaw-start"]`.

## Kit

[`docker.io/sbx/openclaw-kit`](https://hub.docker.com/r/sbx/openclaw-kit)
